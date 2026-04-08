import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";

type R2Config = {
  bucket: string;
  endpoint: string;
  accessKeyId: string;
  secretAccessKey: string;
  publicBaseUrl: string;
};

let cachedClient: S3Client | null = null;
let cachedConfig: R2Config | null = null;

function readR2Config(): R2Config | null {
  const bucket = process.env.R2_BUCKET?.trim();
  const endpoint = process.env.R2_ENDPOINT?.trim();
  const accessKeyId = process.env.R2_ACCESS_KEY_ID?.trim();
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY?.trim();
  const publicBaseUrl = process.env.R2_PUBLIC_BASE_URL?.trim();

  if (!bucket || !endpoint || !accessKeyId || !secretAccessKey || !publicBaseUrl) {
    return null;
  }

  return {
    bucket,
    endpoint,
    accessKeyId,
    secretAccessKey,
    publicBaseUrl: publicBaseUrl.replace(/\/+$/, ""),
  };
}

function getClientAndConfig() {
  if (cachedClient && cachedConfig) {
    return { client: cachedClient, config: cachedConfig };
  }

  const cfg = readR2Config();
  if (!cfg) {
    return null;
  }

  cachedConfig = cfg;
  cachedClient = new S3Client({
    region: "auto",
    endpoint: cfg.endpoint,
    credentials: {
      accessKeyId: cfg.accessKeyId,
      secretAccessKey: cfg.secretAccessKey,
    },
  });
  return { client: cachedClient, config: cfg };
}

export function isR2Configured(): boolean {
  return Boolean(readR2Config());
}

export async function uploadImageToR2(key: string, body: Buffer, mimeType: string): Promise<string> {
  const ctx = getClientAndConfig();
  if (!ctx) {
    throw new Error("R2 storage is not configured");
  }

  await ctx.client.send(
    new PutObjectCommand({
      Bucket: ctx.config.bucket,
      Key: key,
      Body: body,
      ContentType: mimeType,
      CacheControl: "public, max-age=31536000, immutable",
    })
  );

  return `${ctx.config.publicBaseUrl}/${key}`;
}
