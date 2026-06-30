/**
 * Renders a JSON-LD structured-data block. The `<` escaping follows Next.js's
 * JSON-LD guidance to keep the payload safe inside a <script> tag.
 */
export function JsonLd({ data }: { data: object }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(data).replace(/</g, "\\u003c"),
      }}
    />
  );
}
