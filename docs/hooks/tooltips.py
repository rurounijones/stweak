"""Append the glossary tooltip definitions to every page except the glossary.

The `abbr` markdown extension turns *[Term]: definition lines into hover
tooltips, but pymdownx.snippets' auto_append, which would inject them into
every page, has no way to exclude one. So this hook does the appending
itself: every page gets the definitions except glossary.md, where the full
definitions are already right there and a tooltip would be redundant.

See docs/includes/abbreviations.md and mkdocs.yml.
"""

from pathlib import Path

# The hook and the definitions both live under docs/, two levels up from this
# file, so the abbreviations are found relative to it.
ABBREVIATIONS = (
    Path(__file__).resolve().parents[1] / 'includes' / 'abbreviations.md'
)


def on_page_markdown(markdown, page, config, files):
    if page.file.src_uri == 'glossary.md':
        return markdown
    return markdown + '\n\n' + ABBREVIATIONS.read_text()
