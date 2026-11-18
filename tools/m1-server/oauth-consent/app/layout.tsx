import type { Metadata } from "next";
import type { ReactNode } from "react";

export const metadata: Metadata = {
  title: "CheckD OAuth Authorization",
  description: "Review and manage CheckD account access.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="zh-CN">
      <body style={{
        margin: 0,
        minHeight: "100vh",
        background: "#f7f5f2",
        color: "#302b29",
        fontFamily: "system-ui, sans-serif",
      }}>
        {children}
      </body>
    </html>
  );
}
