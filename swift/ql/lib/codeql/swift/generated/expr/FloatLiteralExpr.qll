// generated by codegen/codegen.py
import codeql.swift.elements.expr.NumberLiteralExpr

class FloatLiteralExprBase extends @float_literal_expr, NumberLiteralExpr {
  override string toString() { result = "FloatLiteralExpr" }

  string getStringValue() { float_literal_exprs(this, result) }
}
