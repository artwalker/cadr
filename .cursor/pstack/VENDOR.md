# Vendored pstack

Source: https://github.com/cursor/plugins/tree/main/pstack
Author: Lauren Tan (`@poteto`)
License: MIT (see `LICENSE`)
Pin: `PIN` (cursor/plugins SHA)

This is Cursor's engineering method for developing cadr. It is not a
cadr product feature. Do not load it via `./cadr --skills`. Do not
rewrite files in this tree to look like Lisp. Overlay and cadr-specific
playbooks live in `.cursor/skills/cadr-mode/`.

Refresh:

```sh
git clone --depth 1 --filter=blob:none --sparse https://github.com/cursor/plugins.git /tmp/cursor-plugins
git -C /tmp/cursor-plugins sparse-checkout set pstack
# copy onto .cursor/pstack, keep PIN + VENDOR.md, restore cadr-mode overlay outside this tree
```
