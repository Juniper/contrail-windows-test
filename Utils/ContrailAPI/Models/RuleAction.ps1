class RuleAction {}

class SimplePassRuleAction : RuleAction {
    [Hashtable] GetRequest() {
        return @{ 'simple_action' = 'pass' }
    }
}

class SimpleDenyRuleAction : RuleAction {
    [Hashtable] GetRequest() {
        return @{ 'simple_action' = 'deny' }
    }
}
