from typing import Literal, Dict, Any, List, Tuple
from pydantic import BaseModel
try:
    import yaml  # type: ignore
except Exception:  # pragma: no cover - optional at runtime, covered in env
    yaml = None

NodeType = Literal["llm", "tool", "router"]

class Node(BaseModel):
    name: str
    type: NodeType

class Graph(BaseModel):
    name: str
    nodes: Dict[str, Node]
    inputs: List[str] = []
    edges: List[Tuple[str, str]] = []

def _expand_edge_spec(edge_spec: str, valid_nodes: Dict[str, Node]) -> List[Tuple[str, str]]:
    """Expand a compact edge spec like "(a|b) -> c" into [(a,c),(b,c)].
    Only node names present in valid_nodes are considered; other tokens are ignored.
    """
    parts = edge_spec.split("->")
    if len(parts) != 2:
        return []
    left, right = parts[0].strip(), parts[1].strip()

    def extract_names(expr: str) -> List[str]:
        # Remove parentheses and split on '|' or ',' then strip
        cleaned = expr.replace("(", "").replace(")", "")
        candidates = [t.strip() for t in cleaned.replace("|", ",").split(",")]
        # Only keep names that are declared nodes
        return [t for t in candidates if t in valid_nodes]

    left_names = extract_names(left)
    right_names = extract_names(right)
    edges: List[Tuple[str, str]] = []
    if not right_names and right in valid_nodes:
        right_names = [right]
    for ln in left_names:
        for rn in right_names or ([right] if right in valid_nodes else []):
            edges.append((ln, rn))
    return edges


def compile_graph(manifest: Dict[str, Any]) -> Graph:
    nodes = {k: Node(name=k, type=v.get("type", "tool")) for k, v in manifest.get("nodes", {}).items()}
    inputs = list(manifest.get("inputs", []) or [])
    edge_specs: List[str] = list(manifest.get("edges", []) or [])
    edges: List[Tuple[str, str]] = []
    for spec in edge_specs:
        edges.extend(_expand_edge_spec(spec, nodes))
    return Graph(name=manifest.get("graph", "unnamed"), nodes=nodes, inputs=inputs, edges=edges)


def compile_graph_from_yaml(yaml_text: str) -> Graph:
    if yaml is None:
        raise RuntimeError("pyyaml is required to compile from YAML. Please install pyyaml.")
    manifest = yaml.safe_load(yaml_text) or {}
    if not isinstance(manifest, dict):
        raise ValueError("YAML must define a mapping at the root")
    return compile_graph(manifest)
