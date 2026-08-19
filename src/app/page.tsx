import Display from "@/components/Display";
import Gate from "@/components/Gate";

export const dynamic = "force-dynamic";

export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ demo?: string; view?: string }>;
}) {
  const { demo, view } = await searchParams;
  const initialView = view === "week" || view === "day" ? view : undefined;

  if (demo === "1") return <Display demo initialView={initialView} />;

  const configured = Boolean(
    process.env.AUTH_GOOGLE_ID && process.env.AUTH_GOOGLE_SECRET && process.env.AUTH_SECRET,
  );
  if (!configured) return <Gate configured={false} />;

  // Only import auth once the env is present — otherwise Auth.js throws on init.
  const { auth } = await import("@/auth");
  const session = await auth();
  if (!session || session.error) return <Gate configured />;

  return <Display initialView={initialView} />;
}
