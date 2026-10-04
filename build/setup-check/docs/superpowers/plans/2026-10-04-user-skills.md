# User Skills Plan

**Goal:** the user can add their own skills (instructions for the agent). The agent sees a list of them and loads the full text when it needs it.

**Out of scope:** MCP (separate stage later: remote Streamable HTTP, tools only, Bearer header, no OAuth), skills saved by the agent, built-in/seeded skills, import from file/URL.

## Decisions

- Skill = `{id, name, description, body, enabled}`. Name required, unique (case-insensitive), max 60 chars; description required, max 200; body max 4000.
- Stored as a JSON array under key `skills` in the existing Preferences store `settings` (value limit 16 MB, so no concern). The agent service reads it with `dropCache` at task start; the set is frozen for the run.
- Progressive disclosure: the system prompt gets a `Skills` section with `- name: description` for enabled skills; tool `read_skill({name})` with `name` as an enum of enabled skill names returns the body. The tool is only sent when at least one skill is enabled.
- Step text: `Read skill: <name>`. Counts toward the 25-step limit.
- UI: new icon in the `Index` header next to Settings opens `pages/Skills` (list: name, one-line description, toggle; "+" in the header). Tap opens `pages/SkillEdit` (Name, Description, Body, counters, inline errors, Save, Delete with confirmation). Empty state: "No skills yet. Skills teach the agent how to handle specific apps or tasks. Tap + to add one."
- English UI copy, colors via `$r('app.color.*')`, same look as `Settings`.

## Tasks

1. **Skill model** (`agent/Skills.ets` + `Skills.test.ets`): type, tolerant JSON parse/serialize, validation, prompt section builder.
2. **`read_skill` tool** (`agent/Tools.ets`, `agent/StepText.ets` + tests): tool definition with enum, parsing (case-insensitive name match, error when unknown or no skills), step text.
3. **Pass prompt and tools to the model** (`agent/Providers.ets`): `createLlm` takes `system` and `tools` (defaults: today's `SYSTEM_PROMPT` and `TOOLS`), so existing calls keep working. This also prepares the ground for MCP.
4. **Loop + service** (`agent/AgentLoop.ets`, `a11y/AgentA11y.ets`, `common/Settings.ets` + `AgentLoop.test.ets`): `loadSkills`/`saveSkills`; the service loads skills at task start and passes them to `createLlm` and `AgentLoop`; the loop handles `read_skill`.
5. **UI** (`pages/Skills.ets`, `pages/SkillEdit.ets`, `pages/Index.ets`, `main_pages.json`, icons `ic_skills.svg` / `ic_add.svg`): list, editor, header entry point.

Each task ends with `.\scripts\test.ps1` green.

## Checks before done

- Emulator: add a skill → run a task in its area → the timeline shows `Read skill: …` and the agent follows it.
- Disabled skill does not appear in the prompt and cannot be read.
- Corrupt `skills` JSON does not crash the app (list is empty).
- Renaming a skill to a different-case version of its own name is allowed; a duplicate name is rejected.
- Back from the editor without Save discards changes; header icons fit at 360 px width.
