import agentLoopTest from './AgentLoop.test';
import anthropicTest from './Anthropic.test';
import geminiTest from './Gemini.test';
import openAiCompatTest from './OpenAiCompat.test';
import providersTest from './Providers.test';
import screenTextTest from './ScreenText.test';
import toolsTest from './Tools.test';

export default function testsuite() {
  screenTextTest();
  toolsTest();
  anthropicTest();
  openAiCompatTest();
  geminiTest();
  providersTest();
  agentLoopTest();
}
