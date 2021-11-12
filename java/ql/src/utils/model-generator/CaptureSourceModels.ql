/**
 * @name Capture source models.
 * @description Finds APIs that act as sources as they expose already known sources.
 * @id java/utils/model-generator/sink-models
 */

import java
private import Telemetry.ExternalAPI
private import semmle.code.java.dataflow.DataFlow
private import semmle.code.java.dataflow.TaintTracking
private import semmle.code.java.dataflow.ExternalFlow
private import ModelGeneratorUtils
private import semmle.code.java.dataflow.internal.FlowSummaryImplSpecific
private import semmle.code.java.dataflow.internal.FlowSummaryImpl
private import semmle.code.java.dataflow.internal.DataFlowImplCommon
private import semmle.code.java.dataflow.internal.DataFlowNodes::Private

class FromSourceConfiguration extends TaintTracking::Configuration {
  FromSourceConfiguration() { this = "FromSourceConfiguration" }

  override predicate isSource(DataFlow::Node source) { sourceNode(source, _) }

  override predicate isSink(DataFlow::Node sink) {
    exists(Callable c |
      sink instanceof ReturnNodeExt and
      sink.getEnclosingCallable() = c and
      c.isPublic() and
      c.fromSource()
    )
    or
    exists(MethodAccess c | sink.asExpr() = c.getAnArgument())
  }

  override DataFlow::FlowFeature getAFeature() {
    result instanceof DataFlow::FeatureHasSinkCallContext
  }
}

string asOutput(DataFlow::Node node) {
  if node instanceof ReturnNodeExt
  then result = "ReturnValue"
  else
    result =
      "Parameter[" +
        node.(ArgumentNode)
            .getCall()
            .asCall()
            .getQualifier()
            .(VarAccess)
            .getVariable()
            .(Parameter)
            .getPosition() + "]"
}

string captureSource(Callable api) {
  exists(DataFlow::Node source, DataFlow::Node sink, FromSourceConfiguration config, string kind |
    config.hasFlow(source, sink) and
    sourceNode(source, kind) and
    api = source.getEnclosingCallable() and
    result = asSourceModel(api, asOutput(sink), kind)
  )
}

from TargetAPI api, string sink
where sink = captureSource(api)
select sink order by sink
