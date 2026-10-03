import agentLoopTest from './AgentLoop.test';
import anthropicTest from './Anthropic.test';
import screenTextTest from './ScreenText.test';
import toolsTest from './Tools.test';

export default function testsuite() {
  screenTextTest();
  toolsTest();
  anthropicTest();
  agentLoopTest();
}
