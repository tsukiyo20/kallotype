# Skills

Vendored, not written here.

Each directory is one skill in the
[Agent Skills](https://github.com/anthropics/skills) layout: a `SKILL.md` with
YAML front matter, which an agent reads when the task matches its description.

| | |
|---|---|
| [flutter/agent-plugins](https://github.com/flutter/agent-plugins) | 25 skills, at `b7d5a0b` |
| [dart-lang/skills](https://github.com/dart-lang/skills) | the same 15 `dart-*` skills, at `fa69167` |

The fifteen `dart-*` skills are byte-identical in both repositories;
`flutter/agent-plugins` vendors them. The union is 25.

They are copied here because the repository is developed on two machines, and a
vendored copy is the same on both. They are **not modified**: a fix belongs
upstream.

## Refreshing

```bash
git clone --depth 1 https://github.com/flutter/agent-plugins /tmp/agent-plugins
git clone --depth 1 https://github.com/dart-lang/skills /tmp/dart-skills
cp -r /tmp/agent-plugins/skills/. .agents/skills/
```

Then update the hashes above, and keep the two licence files.

## Licence

`LICENSE-flutter-agent-plugins` (BSD-3-Clause, The Flutter Authors) and
`LICENSE-dart-lang-skills` (BSD-3-Clause, the Dart project authors) cover these
files and are retained as their terms require. The rest of this repository is
MIT or Apache-2.0.
