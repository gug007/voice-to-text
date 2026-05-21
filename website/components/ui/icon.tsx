import type { SVGProps } from "react";

export type IconName =
  | "agent"
  | "apps"
  | "arrow-right"
  | "bolt"
  | "box"
  | "chevron-down"
  | "cloud"
  | "download"
  | "github"
  | "keyboard"
  | "lock"
  | "mic"
  | "sparkle";

type IconProps = SVGProps<SVGSVGElement> & {
  name: IconName;
  size?: "sm" | "md" | "lg";
};

const sizeClass: Record<NonNullable<IconProps["size"]>, string> = {
  sm: "icon icon--sm",
  md: "icon",
  lg: "icon icon--lg",
};

export function Icon({ name, size = "md", className, ...props }: IconProps) {
  const cls = className ? `${sizeClass[size]} ${className}` : sizeClass[size];
  return (
    <svg className={cls} aria-hidden="true" {...props}>
      <use href={`#i-${name}`} />
    </svg>
  );
}
