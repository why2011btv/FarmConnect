import { Pool } from "pg";
import { createId } from "../lib/id.js";
import { Category, Comment, Post, TimeFilter } from "../types.js";

type ListPostFilters = {
  query?: string;
  category?: "all" | Category;
  timeFilter?: TimeFilter;
  visibility?: "all" | "Public" | "Private";
  userId?: string;
};

type CreatePostInput = Omit<Post, "id" | "createdAt" | "upvotes" | "comments">;
type AddCommentInput = Pick<Comment, "text" | "userId" | "userName">;

type PostRow = {
  id: string;
  title: string;
  body: string;
  crop: string;
  category: Category;
  severity: number;
  visibility: "Public" | "Private";
  lat: number;
  lng: number;
  city: string;
  created_at: string;
  upvotes: number;
  user_id: string;
  user_name: string;
  image_url: string | null;
  image_urls: string[] | null;
};

type CommentRow = {
  id: string;
  post_id: string;
  text: string;
  user_id: string;
  user_name: string;
  created_at: string;
};

function getCutoff(filter: TimeFilter): number {
  const now = Date.now();
  switch (filter) {
    case "1h":
      return now - 1 * 60 * 60 * 1000;
    case "5h":
      return now - 5 * 60 * 60 * 1000;
    case "1d":
      return now - 24 * 60 * 60 * 1000;
    case "3d":
      return now - 3 * 24 * 60 * 60 * 1000;
    case "1w":
      return now - 7 * 24 * 60 * 60 * 1000;
    case "3w":
      return now - 21 * 24 * 60 * 60 * 1000;
    case "all":
      return 0;
  }
}

function toPost(row: PostRow, comments: Comment[]): Post {
  const normalizedImageUrls = (row.image_urls ?? []).filter((value) => value.trim().length > 0);
  const fallbackImageUrl = row.image_url ?? undefined;
  const imageUrls = normalizedImageUrls.length > 0
    ? normalizedImageUrls
    : (fallbackImageUrl ? [fallbackImageUrl] : []);

  return {
    id: row.id,
    title: row.title,
    body: row.body,
    crop: row.crop,
    category: row.category,
    severity: row.severity as 1 | 2 | 3 | 4 | 5,
    visibility: row.visibility,
    lat: row.lat,
    lng: row.lng,
    city: row.city,
    createdAt: Number(row.created_at),
    upvotes: row.upvotes,
    comments,
    userId: row.user_id,
    userName: row.user_name,
    imageUrl: imageUrls[0],
    imageUrls,
  };
}

function toComment(row: CommentRow): Comment {
  return {
    id: row.id,
    postId: row.post_id,
    text: row.text,
    userId: row.user_id,
    userName: row.user_name,
    createdAt: Number(row.created_at),
  };
}

export class PostRepository {
  constructor(private readonly db: Pool) {}

  async list(filters: ListPostFilters): Promise<Post[]> {
    const {
      query = "",
      category = "all",
      timeFilter = "all",
      visibility = "all",
      userId,
    } = filters;

    const clauses: string[] = [];
    const params: unknown[] = [];

    if (timeFilter !== "all") {
      params.push(getCutoff(timeFilter));
      clauses.push(`p.created_at >= $${params.length}`);
    }

    if (visibility !== "all") {
      params.push(visibility);
      clauses.push(`p.visibility = $${params.length}`);
    }

    if (category !== "all") {
      params.push(category);
      clauses.push(`p.category = $${params.length}`);
    }

    if (userId && visibility === "Private") {
      params.push(userId);
      clauses.push(`p.user_id = $${params.length}`);
    }

    if (query.trim()) {
      params.push(`%${query.trim().toLowerCase()}%`);
      const idx = params.length;
      clauses.push(`
        (
          LOWER(p.title) LIKE $${idx}
          OR LOWER(p.body) LIKE $${idx}
          OR LOWER(p.crop) LIKE $${idx}
          OR LOWER(p.category) LIKE $${idx}
        )
      `);
    }

    const whereClause = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
    const { rows } = await this.db.query<PostRow>(
      `
      SELECT
        p.id, p.title, p.body, p.crop, p.category, p.severity, p.visibility,
        p.lat, p.lng, p.city, p.created_at, p.upvotes, p.user_id, u.name AS user_name, p.image_url, p.image_urls
      FROM posts p
      JOIN users u ON u.id = p.user_id
      ${whereClause}
      ORDER BY p.created_at DESC
      `
    , params);

    if (rows.length === 0) return [];

    const postIds = rows.map((r) => r.id);
    const { rows: commentRows } = await this.db.query<CommentRow>(
      `
      SELECT id, post_id, text, user_id, user_name, created_at
      FROM comments
      WHERE post_id = ANY($1::text[])
      ORDER BY created_at DESC
      `,
      [postIds]
    );

    const commentsByPost = new Map<string, Comment[]>();
    for (const row of commentRows) {
      const mapped = toComment(row);
      const list = commentsByPost.get(mapped.postId) ?? [];
      list.push(mapped);
      commentsByPost.set(mapped.postId, list);
    }

    return rows.map((row) => toPost(row, commentsByPost.get(row.id) ?? []));
  }

  async create(input: CreatePostInput): Promise<Post> {
    const id = createId("p");
    const createdAt = Date.now();
    const normalizedImageUrls = (input.imageUrls ?? [])
      .map((value) => value.trim())
      .filter((value) => value.length > 0);
    const fallbackImageUrl = input.imageUrl?.trim();
    const imageUrls = normalizedImageUrls.length > 0
      ? normalizedImageUrls
      : (fallbackImageUrl ? [fallbackImageUrl] : []);
    const primaryImageUrl = imageUrls[0] ?? null;

    const { rows } = await this.db.query<PostRow>(
      `
      INSERT INTO posts (
        id, title, body, crop, category, severity, visibility, lat, lng, city,
        created_at, upvotes, user_id, image_url, image_urls
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 0, $12, $13, $14)
      RETURNING id, title, body, crop, category, severity, visibility, lat, lng, city,
        created_at, upvotes, user_id, image_url, image_urls
      `,
      [
        id, input.title, input.body, input.crop, input.category, input.severity,
        input.visibility, input.lat, input.lng, input.city, createdAt, input.userId, primaryImageUrl, imageUrls,
      ]
    );

    const row = rows[0];
    return {
      ...toPost({ ...row, user_name: input.userName }, []),
      userName: input.userName,
    };
  }

  async upvote(postId: string, userId: string): Promise<Post | null> {
    const exists = await this.db.query<{ id: string }>("SELECT id FROM posts WHERE id = $1", [postId]);
    if (!exists.rowCount) return null;

    const insertResult = await this.db.query(
      `
      INSERT INTO post_upvotes (post_id, user_id, created_at)
      VALUES ($1, $2, $3)
      ON CONFLICT (post_id, user_id) DO NOTHING
      `,
      [postId, userId, Date.now()]
    );

    if (insertResult.rowCount) {
      await this.db.query("UPDATE posts SET upvotes = upvotes + 1 WHERE id = $1", [postId]);
    }

    const posts = await this.listByIds([postId]);
    return posts[0] ?? null;
  }

  async addComment(postId: string, input: AddCommentInput): Promise<{ comment: Comment; post: Post } | null> {
    const commentId = createId("c");
    const createdAt = Date.now();

    const { rowCount } = await this.db.query(
      `
      INSERT INTO comments (id, post_id, text, user_id, user_name, created_at)
      VALUES ($1, $2, $3, $4, $5, $6)
      `,
      [commentId, postId, input.text, input.userId, input.userName, createdAt]
    );
    if (!rowCount) return null;

    const comment: Comment = {
      id: commentId,
      postId,
      text: input.text,
      userId: input.userId,
      userName: input.userName,
      createdAt,
    };

    const post = (await this.listByIds([postId]))[0];
    if (!post) return null;
    return { comment, post };
  }

  async getById(postId: string): Promise<Post | null> {
    const posts = await this.listByIds([postId]);
    return posts[0] ?? null;
  }

  private async listByIds(ids: string[]): Promise<Post[]> {
    if (!ids.length) return [];
    const { rows } = await this.db.query<PostRow>(
      `
      SELECT
        p.id, p.title, p.body, p.crop, p.category, p.severity, p.visibility,
        p.lat, p.lng, p.city, p.created_at, p.upvotes, p.user_id, u.name AS user_name, p.image_url, p.image_urls
      FROM posts p
      JOIN users u ON u.id = p.user_id
      WHERE p.id = ANY($1::text[])
      ORDER BY p.created_at DESC
      `,
      [ids]
    );
    if (!rows.length) return [];

    const { rows: commentRows } = await this.db.query<CommentRow>(
      `
      SELECT id, post_id, text, user_id, user_name, created_at
      FROM comments
      WHERE post_id = ANY($1::text[])
      ORDER BY created_at DESC
      `,
      [ids]
    );

    const commentsByPost = new Map<string, Comment[]>();
    for (const row of commentRows) {
      const mapped = toComment(row);
      const list = commentsByPost.get(mapped.postId) ?? [];
      list.push(mapped);
      commentsByPost.set(mapped.postId, list);
    }

    return rows.map((row) => toPost(row, commentsByPost.get(row.id) ?? []));
  }
}
