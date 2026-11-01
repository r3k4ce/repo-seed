import { useEffect, useState } from "react";

type Health = {
  status: string;
  project: string;
};

export default function App() {
  const [health, setHealth] = useState<Health | null>(null);

  useEffect(() => {
    fetch("/api/health")
      .then((response) => response.json() as Promise<Health>)
      .then(setHealth)
      .catch(() => setHealth({ status: "offline", project: "demo-app" }));
  }, []);

  return (
    <main>
      <h1>demo-app</h1>
      <p>Backend: {health ? health.project + " " + health.status : "checking..."}</p>
    </main>
  );
}
