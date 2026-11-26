import 'agent_school_browser_contract.dart';
import 'agent_school_browser_fallback.dart'
    if (dart.library.io) 'agent_school_browser_native.dart'
    if (dart.library.js_interop) 'agent_school_browser_web.dart'
    as platform;

export 'agent_school_browser_contract.dart';

AgentSchoolBrowser createAgentSchoolBrowser() => platform.createSchoolBrowser();
