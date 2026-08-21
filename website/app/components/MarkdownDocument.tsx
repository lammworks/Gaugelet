import type { ReactNode } from "react";

type MarkdownDocumentProps = {
  eyebrow: string;
  source: string;
};

function inlineMarkdown(value: string): ReactNode[] {
  const pattern = /(\[[^\]]+\]\([^)]+\)|`[^`]+`|\*\*[^*]+\*\*)/g;

  const siteHref = (href: string) => {
    const [path, fragment] = href.split("#", 2);
    const routes: Record<string, string> = {
      "README.md": "/",
      "INSTALL.md": "/install",
      "PRIVACY.md": "/privacy",
      "SUPPORT.md": "/support",
      "SECURITY.md": "/security",
      "CHANGELOG.md": "/changelog",
    };
    const route = routes[path];
    if (route) return fragment ? `${route}#${fragment}` : route;
    if (/^(?:[A-Z0-9_-]+\.md|LICENSE)$/i.test(path)) {
      return `https://github.com/lammworks/Gaugelet/blob/main/${href}`;
    }
    return href;
  };

  return value.split(pattern).filter(Boolean).map((part, index) => {
    const link = part.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
    if (link) {
      return <a href={siteHref(link[2])} key={`${part}-${index}`}>{link[1]}</a>;
    }
    if (part.startsWith("`") && part.endsWith("`")) {
      return <code key={`${part}-${index}`}>{part.slice(1, -1)}</code>;
    }
    if (part.startsWith("**") && part.endsWith("**")) {
      return <strong key={`${part}-${index}`}>{part.slice(2, -2)}</strong>;
    }
    return part;
  });
}

export function MarkdownDocument({ eyebrow, source }: MarkdownDocumentProps) {
  const lines = source.replace(/\r\n/g, "\n").split("\n");
  const blocks: ReactNode[] = [];
  let paragraph: string[] = [];
  let list: Array<{ ordered: boolean; text: string }> = [];
  let code: string[] | null = null;
  let table: string[][] = [];

  const flushParagraph = () => {
    if (!paragraph.length) return;
    blocks.push(<p key={`p-${blocks.length}`}>{inlineMarkdown(paragraph.join(" "))}</p>);
    paragraph = [];
  };
  const flushList = () => {
    if (!list.length) return;
    const ordered = list[0].ordered;
    const items = list.map((item, index) => (
      <li key={`${item.text}-${index}`}>{inlineMarkdown(item.text)}</li>
    ));
    blocks.push(ordered
      ? <ol key={`ol-${blocks.length}`}>{items}</ol>
      : <ul key={`ul-${blocks.length}`}>{items}</ul>);
    list = [];
  };
  const flushTable = () => {
    if (table.length < 2) {
      if (table.length === 1) paragraph.push(table[0].join(" | "));
      table = [];
      return;
    }
    const [head, divider, ...rows] = table;
    const isTable = divider.every((cell) => /^:?-{3,}:?$/.test(cell.trim()));
    if (!isTable) {
      paragraph.push(...table.map((row) => row.join(" | ")));
      table = [];
      return;
    }
    blocks.push(
      <div className="table-wrap" key={`table-${blocks.length}`}>
        <table>
          <thead><tr>{head.map((cell, index) => <th key={index}>{inlineMarkdown(cell.trim())}</th>)}</tr></thead>
          <tbody>
            {rows.map((row, rowIndex) => (
              <tr key={rowIndex}>{row.map((cell, index) => <td key={index}>{inlineMarkdown(cell.trim())}</td>)}</tr>
            ))}
          </tbody>
        </table>
      </div>
    );
    table = [];
  };

  for (const rawLine of lines) {
    const line = rawLine.trimEnd();
    const contentLine = line.trimStart();
    if (line.startsWith("```")) {
      flushParagraph(); flushList(); flushTable();
      if (code) {
        blocks.push(<pre key={`code-${blocks.length}`}><code>{code.join("\n")}</code></pre>);
        code = null;
      } else {
        code = [];
      }
      continue;
    }
    if (code) {
      code.push(rawLine);
      continue;
    }
    if (/^\|.+\|$/.test(line)) {
      flushParagraph(); flushList();
      table.push(line.slice(1, -1).split("|"));
      continue;
    }
    flushTable();
    if (!line.trim()) {
      flushParagraph(); flushList();
      continue;
    }
    const heading = contentLine.match(/^(#{1,4})\s+(.+)$/);
    if (heading) {
      flushParagraph(); flushList();
      const level = heading[1].length;
      const content = inlineMarkdown(heading[2]);
      if (level === 1) blocks.push(<h1 key={`h-${blocks.length}`}>{content}</h1>);
      if (level === 2) blocks.push(<h2 key={`h-${blocks.length}`}>{content}</h2>);
      if (level === 3) blocks.push(<h3 key={`h-${blocks.length}`}>{content}</h3>);
      if (level === 4) blocks.push(<h4 key={`h-${blocks.length}`}>{content}</h4>);
      continue;
    }
    const unordered = contentLine.match(/^[-*]\s+(.+)$/);
    const ordered = contentLine.match(/^\d+\.\s+(.+)$/);
    if (unordered || ordered) {
      flushParagraph();
      list.push({ ordered: Boolean(ordered), text: (unordered ?? ordered)![1] });
      continue;
    }
    if (/^---+$/.test(line)) {
      flushParagraph(); flushList();
      blocks.push(<hr key={`hr-${blocks.length}`} />);
      continue;
    }
    if (line.startsWith("> ")) {
      flushParagraph(); flushList();
      blocks.push(<blockquote key={`quote-${blocks.length}`}>{inlineMarkdown(line.slice(2))}</blockquote>);
      continue;
    }
    paragraph.push(line.trim());
  }

  flushParagraph(); flushList(); flushTable();
  if (code) blocks.push(<pre key={`code-${blocks.length}`}><code>{code.join("\n")}</code></pre>);

  return (
    <article className="document-shell">
      <p className="document-eyebrow">{eyebrow}</p>
      <div className="markdown-body">{blocks}</div>
    </article>
  );
}
