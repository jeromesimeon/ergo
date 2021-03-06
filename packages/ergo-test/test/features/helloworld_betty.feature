Feature: Betty Buyer's Hello World
  This describe the expected behavior for the Accord Project's helloworld contract for Betty Buyer

  Background:
    Given the Ergo contract "org.accordproject.helloworld.HelloWorld" in file "../../../tests/helloworld/logic/logic.ergo"
    Given the model in file "../../../tests/helloworld/model/model.cto"
    Given the contract data
"""
{
  "$class": "org.accordproject.helloworld.TemplateModel",
  "name": "Betty Buyer"
}
"""

  Scenario: The contract says hello to Betty Buyer from ACME
    When it receives the request
"""
{
    "$class": "org.accordproject.helloworld.Request",
    "input": "ACME"
}
"""
    Then it should respond with
"""
{
  "$class": "org.accordproject.helloworld.Response",
  "output" : "Hello Betty Buyer (ACME)"
}
"""
    And the new state of the contract should be
"""
{
  "$class":"org.accordproject.runtime.State"
}
"""

