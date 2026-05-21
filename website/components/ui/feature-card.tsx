import type { ReactNode } from "react";
import { Icon, type IconName } from "./icon";

type FeatureCardProps = {
  icon: IconName;
  title: ReactNode;
  children: ReactNode;
};

export function FeatureCard({ icon, title, children }: FeatureCardProps) {
  return (
    <li className="feature-card">
      <div className="feature-card__icon" aria-hidden="true">
        <Icon name={icon} size="lg" />
      </div>
      <h3 className="feature-card__title">{title}</h3>
      <p className="feature-card__body">{children}</p>
    </li>
  );
}
