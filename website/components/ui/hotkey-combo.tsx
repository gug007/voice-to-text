type HotkeyComboProps = {
  /** Modifier glyph shown visually. Default: ⌥ (Option). */
  modifier?: string;
  /** Modifier name spoken to screen readers. Default: "Option". */
  modifierName?: string;
  /** Second key glyph shown visually. Default: "Space". */
  secondary?: string;
};

export function HotkeyCombo({
  modifier = "⌥",
  modifierName = "Option",
  secondary = "Space",
}: HotkeyComboProps = {}) {
  return (
    <span className="kbd-combo">
      <span className="sr-only">{`${modifierName} plus ${secondary}`}</span>
      <kbd className="keycap keycap--inline" aria-hidden="true">{modifier}</kbd>
      <kbd className="keycap keycap--inline" aria-hidden="true">{secondary}</kbd>
    </span>
  );
}
