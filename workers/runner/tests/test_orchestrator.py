from runner.orchestrator import compile_graph, compile_graph_from_yaml

def test_compile_graph_basic():
    manifest = {"graph": "g1", "nodes": {"n1": {"type": "tool"}, "n2": {"type": "llm"}}}
    g = compile_graph(manifest)
    assert g.name == "g1"
    assert set(g.nodes.keys()) == {"n1","n2"}


def test_compile_graph_from_yaml_edges_and_inputs():
    yaml_text = """
graph: clinical_note_v15
inputs:
  - transcript_uri
  - emr_context_json
nodes:
  a: {type: tool}
  b: {type: tool}
  c: {type: llm}
edges:
  - (a|b) -> c
    """
    g = compile_graph_from_yaml(yaml_text)
    assert g.inputs == ["transcript_uri", "emr_context_json"]
    assert set(g.nodes.keys()) == {"a","b","c"}
    assert ("a","c") in g.edges and ("b","c") in g.edges
