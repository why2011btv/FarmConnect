import { FastifyInstance } from "fastify";
import { Pool } from "pg";
import { z } from "zod";
import { requireAuth } from "../auth/requireAuth.js";
import { PostRepository } from "../repositories/postRepository.js";
import { moderateUserContent } from "../services/moderationService.js";
import { queueNearbyPostNotifications, queuePushNotification } from "../services/notificationService.js";
import { Category, TimeFilter } from "../types.js";

const categoryValues: Category[] = ["Disease", "Pest", "Weather", "Note", "Market"];
const timeFilterValues: TimeFilter[] = ["1h", "5h", "1d", "3d", "1w", "3w", "all"];

const listQuerySchema = z.object({
  query: z.string().optional(),
  category: z.enum(["all", ...categoryValues]).optional(),
  timeFilter: z.enum(timeFilterValues).optional(),
  visibility: z.enum(["all", "Public", "Private"]).optional(),
  userId: z.string().optional(),
});

const createPostSchema = z.object({
  title: z.string().min(1),
  body: z.string().min(1),
  crop: z.string().min(1),
  category: z.enum(categoryValues),
  severity: z.union([z.literal(1), z.literal(2), z.literal(3), z.literal(4), z.literal(5)]),
  visibility: z.enum(["Public", "Private"]),
  lat: z.number(),
  lng: z.number(),
  city: z.string().min(1),
  imageUrl: z.string().optional(),
  imageUrls: z.array(z.string()).max(10).optional(),
});

const addCommentSchema = z.object({
  text: z.string().min(1),
});

export async function postRoutes(app: FastifyInstance, postRepository: PostRepository, db: Pool) {
  app.get("/v1/posts", async (req, reply) => {
    const parsed = listQuerySchema.safeParse(req.query);
    if (!parsed.success) return app.httpErrors.badRequest(parsed.error.message);

    const query = parsed.data;
    if (query.visibility === "Private") {
      const authUser = await requireAuth(req, reply, db);
      if (!authUser) return;
      query.userId = authUser.id;
    }

    const list = await postRepository.list(query);
    return { items: list };
  });

  app.post("/v1/posts", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const parsed = createPostSchema.safeParse(req.body);
    if (!parsed.success) return app.httpErrors.badRequest(parsed.error.message);

    const moderation = await moderateUserContent(app.log, {
      text: [parsed.data.title, parsed.data.body, parsed.data.crop].join("\n"),
      imageUrls: parsed.data.imageUrls ?? (parsed.data.imageUrl ? [parsed.data.imageUrl] : []),
    });
    if (!moderation.allowed) {
      return reply.code(400).send({
        error: `Content violates platform rule: ${moderation.reason ?? "inappropriate content detected"}`,
      });
    }

    const post = await postRepository.create({
      ...parsed.data,
      userId: authUser.id,
      userName: authUser.name,
    });

    if (post.visibility === "Public") {
      await queueNearbyPostNotifications(db, app.log, {
        authorUserId: authUser.id,
        authorName: authUser.name,
        title: post.title,
        category: post.category,
        lat: post.lat,
        lng: post.lng,
      });
    }

    return { item: post };
  });

  app.post("/v1/posts/:postId/upvote", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const postId = (req.params as { postId: string }).postId;
    const p = await postRepository.upvote(postId, authUser.id);
    if (!p) return app.httpErrors.notFound("Post not found");
    return { item: p };
  });

  app.post("/v1/posts/:postId/comments", async (req, reply) => {
    const authUser = await requireAuth(req, reply, db);
    if (!authUser) return;

    const postId = (req.params as { postId: string }).postId;
    const parsed = addCommentSchema.safeParse(req.body);
    if (!parsed.success) return app.httpErrors.badRequest(parsed.error.message);

    const moderation = await moderateUserContent(app.log, {
      text: parsed.data.text,
    });
    if (!moderation.allowed) {
      return reply.code(400).send({
        error: `Content violates platform rule: ${moderation.reason ?? "inappropriate content detected"}`,
      });
    }

    const result = await postRepository.addComment(postId, {
      text: parsed.data.text,
      userId: authUser.id,
      userName: authUser.name,
    });
    if (!result) return app.httpErrors.notFound("Post not found");

    if (result.post.userId !== authUser.id) {
      await queuePushNotification(
        db,
        app.log,
        result.post.userId,
        "New comment on your post",
        `${authUser.name}: ${parsed.data.text}`
      );
    }
    return { item: result.comment, post: result.post };
  });
}
