"use client";

import { FormEvent, useState } from "react";
import { createCheckdSupabaseBrowserClient } from "../../lib/supabaseBrowser";

export default function LoginForm({ returnTo }: { returnTo: string }) {
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setFailed(false);
    const form = new FormData(event.currentTarget);
    const email = form.get("email");
    const password = form.get("password");
    if (typeof email !== "string" || typeof password !== "string" || !email || !password) {
      setFailed(true);
      setBusy(false);
      return;
    }
    try {
      const supabase = createCheckdSupabaseBrowserClient();
      const { data, error } = await supabase.auth.signInWithPassword({ email, password });
      if (error || !data.user) throw new Error("sign_in_failed");
      window.location.assign(returnTo);
    } catch {
      setFailed(true);
      setBusy(false);
    }
  }

  return (
    <form onSubmit={submit}>
      <label style={{ display: "block", marginBottom: 12 }}>
        邮箱
        <input name="email" type="email" autoComplete="username" required
          style={{ display: "block", boxSizing: "border-box", width: "100%", padding: 10 }} />
      </label>
      <label style={{ display: "block", marginBottom: 16 }}>
        密码
        <input name="password" type="password" autoComplete="current-password" required
          style={{ display: "block", boxSizing: "border-box", width: "100%", padding: 10 }} />
      </label>
      {failed && <p role="alert">无法登录。请确认账号信息或稍后再试。</p>}
      <button type="submit" disabled={busy}>
        {busy ? "正在登录…" : "登录并返回授权"}
      </button>
    </form>
  );
}
