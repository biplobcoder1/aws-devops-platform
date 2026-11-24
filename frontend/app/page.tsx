"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";

type Status = "todo" | "doing" | "done";
type Task = { id: number; title: string; description: string | null; status: Status };
type Health = { status: string; environment: string; version: string };

// Same-origin requests: in AWS the ALB routes /api/* to the backend service,
// locally the nginx proxy in docker-compose does the same. No CORS needed.
const API = "/api";
const COLUMNS: { key: Status; label: string }[] = [
  { key: "todo", label: "To do" },
  { key: "doing", label: "In progress" },
  { key: "done", label: "Done" },
];

export default function Home() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [title, setTitle] = useState("");
  const [health, setHealth] = useState<Health | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [h, t] = await Promise.all([fetch(`${API}/health`), fetch(`${API}/tasks`)]);
      if (!t.ok) throw new Error(`API returned ${t.status}`);
      setHealth(await h.json());
      setTasks(await t.json());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Could not reach the API");
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function addTask(e: FormEvent) {
    e.preventDefault();
    if (!title.trim()) return;
    await fetch(`${API}/tasks`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: title.trim() }),
    });
    setTitle("");
    load();
  }

  async function move(id: number, status: Status) {
    await fetch(`${API}/tasks/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status }),
    });
    load();
  }

  async function remove(id: number) {
    await fetch(`${API}/tasks/${id}`, { method: "DELETE" });
    load();
  }

  return (
    <main>
      <h1>TaskFlow</h1>
      <p className="sub">
        <span className={`badge ${health ? "ok" : "bad"}`}>API {health ? "healthy" : "unreachable"}</span>
        {health && (
          <>
            <span className="badge">env: {health.environment}</span>
            <span className="badge">version: {health.version.slice(0, 7)}</span>
          </>
        )}
      </p>

      {error && <p className="error">⚠ {error}</p>}

      <form onSubmit={addTask}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Add a task…" maxLength={200} />
        <button type="submit">Add</button>
      </form>

      <div className="board">
        {COLUMNS.map((col) => (
          <section className="col" key={col.key}>
            <h2>
              {col.label} ({tasks.filter((t) => t.status === col.key).length})
            </h2>
            {tasks
              .filter((t) => t.status === col.key)
              .map((t) => (
                <div className="card" key={t.id}>
                  <div>{t.title}</div>
                  <div className="row">
                    <select value={t.status} onChange={(e) => move(t.id, e.target.value as Status)}>
                      {COLUMNS.map((c) => (
                        <option key={c.key} value={c.key}>
                          {c.label}
                        </option>
                      ))}
                    </select>
                    <button className="ghost" onClick={() => remove(t.id)} aria-label="Delete task">
                      ✕
                    </button>
                  </div>
                </div>
              ))}
          </section>
        ))}
      </div>
    </main>
  );
}
