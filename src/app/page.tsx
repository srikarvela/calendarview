import DemoHost from "@/components/DemoHost";

export const dynamic = "force-dynamic";

/**
 * The web entry point is a design harness only — the real app is the Mac
 * app in `macapp/`, which signs into Google natively and needs no server.
 */
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ view?: string; gate?: string }>;
}) {
  const { view, gate } = await searchParams;
  const initialView = view === "week" || view === "day" ? view : undefined;
  return <DemoHost initialView={initialView} gate={gate === "1"} />;
}
