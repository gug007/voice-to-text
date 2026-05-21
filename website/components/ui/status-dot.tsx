export type StatusKind = "ok" | "no" | "partial";

export function StatusDot({ kind }: { kind: StatusKind }) {
  return <span className={`status status--${kind}`} aria-hidden="true" />;
}
