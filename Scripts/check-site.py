#!/usr/bin/env python3
"""Check the landing page before it goes anywhere.

Three things a browser will not tell you until someone has already opened the page:

**Missing assets.** A screenshot renamed by the simulator walk leaves a broken image behind, and
the page still "works" — it just looks abandoned.

**External dependencies.** A font or a script pulled from someone else's server means the page
is offline-fragile and quietly tells a third party who is reading it. This page is meant to have
none, so anything but a link to a real site is a regression.

**Absolute paths.** GitHub Pages serves this from a subdirectory, so a leading slash resolves to
the domain root and nothing loads. It works locally, which is what makes it worth checking.
"""
import os
import re
import sys

PAGE = sys.argv[1] if len(sys.argv) > 1 else "docs/index.html"
ROOT = os.path.dirname(PAGE) or "."

# Attributes that load something. A href on <a> is a link, not a dependency, so it is handled
# separately.
LOADING = re.compile(r'(?:src|poster|data-src)\s*=\s*["\']([^"\']+)["\']', re.IGNORECASE)
STYLESHEET = re.compile(r'<link[^>]+rel=["\']stylesheet["\'][^>]*>', re.IGNORECASE)
LINK_HREF = re.compile(r'<a[^>]+href\s*=\s*["\']([^"\']+)["\']', re.IGNORECASE)
CSS_URL = re.compile(r'url\(\s*["\']?([^"\')]+)["\']?\s*\)')
IMPORT = re.compile(r'@import\s+', re.IGNORECASE)

problems = []


def check_reference(reference, kind):
    if reference.startswith(("data:", "#", "mailto:")):
        return
    if reference.startswith(("http://", "https://", "//")):
        problems.append(f"{kind} loads from another server: {reference}")
        return
    if reference.startswith("/"):
        problems.append(f"{kind} is an absolute path and will not resolve on Pages: {reference}")
        return

    target = os.path.normpath(os.path.join(ROOT, reference.split("?")[0].split("#")[0]))
    if not os.path.exists(target):
        problems.append(f"{kind} points at a file that is not here: {reference}")


def main():
    if not os.path.exists(PAGE):
        print(f"no page at {PAGE}")
        return 1

    with open(PAGE, encoding="utf-8") as handle:
        html = handle.read()

    for reference in LOADING.findall(html):
        check_reference(reference, "an element")

    for reference in CSS_URL.findall(html):
        check_reference(reference, "a stylesheet rule")

    for tag in STYLESHEET.findall(html):
        problems.append(f"an external stylesheet is linked: {tag.strip()[:80]}")

    if IMPORT.search(html):
        problems.append("@import pulls in another stylesheet")

    for reference in LINK_HREF.findall(html):
        if reference.startswith(("http://", "https://")):
            continue  # a link to a real site is the point of a link
        check_reference(reference, "a link")

    if "<h1" not in html.lower():
        problems.append("the page has no <h1>")

    images = re.findall(r"<img\b[^>]*>", html, re.IGNORECASE)
    for image in images:
        if not re.search(r'alt\s*=\s*["\']', image, re.IGNORECASE):
            problems.append(f"an image has no alt text: {image.strip()[:80]}")

    if "prefers-reduced-motion" not in html:
        problems.append("nothing honours prefers-reduced-motion")

    size = len(html.encode("utf-8"))
    print(f"{PAGE}: {size / 1024:.0f} KB, {len(images)} images")

    if problems:
        print(f"\n{len(problems)} problem(s):")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print("nothing missing, nothing external, nothing absolute")
    return 0


if __name__ == "__main__":
    sys.exit(main())
