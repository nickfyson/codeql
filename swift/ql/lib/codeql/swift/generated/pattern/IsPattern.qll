// generated by codegen/codegen.py
import codeql.swift.elements.pattern.Pattern
import codeql.swift.elements.typerepr.TypeRepr

class IsPatternBase extends @is_pattern, Pattern {
  override string toString() { result = "IsPattern" }

  TypeRepr getCastTypeRepr() {
    exists(TypeRepr x |
      is_pattern_cast_type_reprs(this, x) and
      result = x.resolve()
    )
  }

  Pattern getSubPattern() {
    exists(Pattern x |
      is_pattern_sub_patterns(this, x) and
      result = x.resolve()
    )
  }
}
