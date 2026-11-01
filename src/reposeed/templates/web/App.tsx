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
      .catch(() => setHealth({ status: "offline", project: "__PROJECT_NAME__" }));
  }, []);

  return (
    <main>
      <h1>__PROJECT_NAME__</h1>
      <p>Backend: {health ? health.project + " " + health.status : "checking..."}</p>
    </main>
  );
}
