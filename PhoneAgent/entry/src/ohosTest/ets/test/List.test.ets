import agentLoopTest from './AgentLoop.test';
import skillsTest from './Skills.test';
import deviceTimeTest from './DeviceTime.test';
import anthropicTest from './Anthropic.test';
import geminiTest from './Gemini.test';
import openAiCompatTest from './OpenAiCompat.test';
import orbGeometryTest from './OrbGeometry.test';
import providersTest from './Providers.test';
import runCheckTest from './RunCheck.test';
import screenTextTest from './ScreenText.test';
import statusTrackerTest from './StatusTracker.test';
import stepTextTest from './StepText.test';
import timelineTest from './Timeline.test';
import toolsTest from './Tools.test';

export default function testsuite() {
  screenTextTest();
  toolsTest();
  anthropicTest();
  openAiCompatTest();
  geminiTest();
  providersTest();
  agentLoopTest();
  skillsTest();
  deviceTimeTest();
  stepTextTest();
  statusTrackerTest();
  timelineTest();
  runCheckTest();
  orbGeometryTest();
}
