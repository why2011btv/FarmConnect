import { FastifyInstance } from "fastify";
import { z } from "zod";
import { PostRepository } from "../repositories/postRepository.js";
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
  userId: z.string().min(1),
  userName: z.string().min(1),
  imageUrl: z.string().optional(),
});

const addCommentSchema = z.object({
  text: z.string().min(1),
  userId: z.string().min(1),
  userName: z.string().min(1),
});

export async function postRoutes(app: FastifyInstance, postRepository: PostRepository) {
  app.get("/v1/posts", async (req) => {
    const parsed = listQuerySchema.safeParse(req.query);
    if (!parsed.success) return app.httpErrors.badRequest(parsed.error.message);

    const list = await postRepository.list(parsed.data);
    return { items: list };
  });

  app.post("/v1/posts", async (req) => {
    const parsed = createPostSchema.safeParse(req.body);
    if (!parsed.success) return app.httpErrors.badRequest(parsed.error.message);

    const post = await postRepository.create(parsed.data);
    return { item: post };
  });

  app.post("/v1/posts/:postId/upvote", async (req) => {
    const postId = (req.params as { postId: string }).postId;
    const p = await postRepository.upvote(postId);
    if (!p) return app.httpErrors.notFound("Post not found");
    return { item: p };
  });

  app.post("/v1/posts/:postId/comments", async (req) => {
    const postId = (req.params as { postId: string }).postId;
    const parsed = addCommentSchema.safeParse(req.body);
    if (!parsed.success) return app.httpErrors.badRequest(parsed.error.message);

    const result = await postRepository.addComment(postId, parsed.data);
    if (!result) return app.httpErrors.notFound("Post not found");
    return { item: result.comment, post: result.post };
  });
}
