import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import CalendarApp from "@/components/CalendarApp";
import { useNativeSource } from "@/lib/source";
import "@/app/globals.css";

/** The UI as it runs inside CalendarView.app: the native side owns the session. */
function NativeHost() {
  const [snapshot, actions] = useNativeSource();
  return <CalendarApp snapshot={snapshot} actions={actions} />;
}

const container = document.getElementById("root");
if (container) {
  createRoot(container).render(
    <StrictMode>
      <NativeHost />
    </StrictMode>,
  );
}
