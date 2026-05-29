import HeyClaudeKit

print("heyclaude-spike \(HeyClaudeKit.version)")

// Runtime proof that the merged sherpa-onnx static archive both links and
// executes (the Task 9 live-mic loop is built in a later task).
print("sherpa-onnx links: \(HeyClaudeKit.sherpaLinks())")
