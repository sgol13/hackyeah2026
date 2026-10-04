# AI workflow

- **Model**: Claude Code with Opus 5.5
- **Skills**: https://github.com/mattpocock/skills
- **Prompts**: "do research about this, plan, /grill-me, research, implement according to the plan"
- **Workflow**: AI turns out to be really bad in creating good idea so idea was mine, then I asked whether the idea is doable with upper prompt, then just implement, then smaller tasks -> plan with /grill me -> implement -> test + review -> commit
- **How generated output was reviewed, tested and validated**: visually in emulator, tested and validated end 2 end
- **AI feature (model in the harness)**: the task, installed app names and the text of the screen being operated go to the provider picked in the app (Anthropic, OpenAI, xAI or Gemini); each provider's API key stays in app-private storage. Only Anthropic was run with a real key; the other three are covered by unit tests and an invalid-key check against their live APIs.
