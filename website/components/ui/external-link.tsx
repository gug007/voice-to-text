import type { AnchorHTMLAttributes, ReactNode } from "react";

type ExternalLinkProps = Omit<AnchorHTMLAttributes<HTMLAnchorElement>, "target" | "rel"> & {
  href: string;
  children: ReactNode;
};

/** <a> for external destinations — sets target="_blank" and rel="noopener noreferrer" consistently. */
export function ExternalLink({ children, ...props }: ExternalLinkProps) {
  return (
    <a target="_blank" rel="noopener noreferrer" {...props}>
      {children}
    </a>
  );
}
