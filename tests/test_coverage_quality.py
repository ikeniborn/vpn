"""
Test coverage analysis and quality gates for VPN Manager.

This module provides comprehensive test coverage analysis, quality metrics,
and automated quality gates to ensure high code quality and test coverage.
"""

import ast
import json
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

import pytest


@dataclass
class CoverageMetrics:
    """Coverage metrics for code analysis."""
    total_statements: int
    covered_statements: int
    missing_statements: int
    coverage_percentage: float
    branch_coverage_percentage: float
    uncovered_lines: list[int]
    file_path: str


@dataclass
class QualityMetrics:
    """Code quality metrics."""
    total_files: int
    total_lines: int
    test_files: int
    test_lines: int
    complexity_score: float
    documentation_coverage: float
    type_annotation_coverage: float


@dataclass
class TestQualityReport:
    """Comprehensive test quality report."""
    coverage_metrics: dict[str, CoverageMetrics]
    quality_metrics: QualityMetrics
    quality_gates_passed: bool
    violations: list[str]
    recommendations: list[str]
    overall_score: float


class CoverageAnalyzer:
    """Analyze test coverage and generate detailed reports."""

    def __init__(self, source_dir: Path = None, test_dir: Path = None):
        self.source_dir = source_dir or Path("vpn")
        self.test_dir = test_dir or Path("tests")
        self.coverage_threshold = 80.0
        self.branch_coverage_threshold = 70.0

    def analyze_coverage(self) -> dict[str, CoverageMetrics]:
        """Analyze test coverage for all source files."""
        coverage_data = {}

        try:
            # Run coverage analysis
            result = subprocess.run([
                sys.executable, "-m", "coverage", "run", "-m", "pytest", "tests/",
                "--cov=vpn", "--cov-report=xml", "--cov-report=json"
            ], check=False, capture_output=True, text=True, cwd=Path.cwd())

            if result.returncode != 0:
                print(f"Coverage analysis failed: {result.stderr}")
                return {}

            # Parse coverage results
            coverage_data = self._parse_coverage_results()

        except Exception as e:
            print(f"Error running coverage analysis: {e}")

        return coverage_data

    def _parse_coverage_results(self) -> dict[str, CoverageMetrics]:
        """Parse coverage results from XML and JSON reports."""
        coverage_data = {}

        # Parse XML coverage report
        xml_file = Path("coverage.xml")
        if xml_file.exists():
            try:
                tree = ET.parse(xml_file)
                root = tree.getroot()

                for package in root.findall(".//package"):
                    for class_elem in package.findall("classes/class"):
                        filename = class_elem.get("filename", "")
                        if not filename.startswith("vpn/"):
                            continue

                        lines = class_elem.findall("lines/line")
                        total_statements = len(lines)
                        covered_statements = len([l for l in lines if l.get("hits", "0") != "0"])
                        missing_statements = total_statements - covered_statements

                        coverage_percentage = (covered_statements / total_statements * 100) if total_statements > 0 else 0

                        # Extract uncovered lines
                        uncovered_lines = [
                            int(line.get("number", 0))
                            for line in lines
                            if line.get("hits", "0") == "0"
                        ]

                        coverage_data[filename] = CoverageMetrics(
                            total_statements=total_statements,
                            covered_statements=covered_statements,
                            missing_statements=missing_statements,
                            coverage_percentage=coverage_percentage,
                            branch_coverage_percentage=0.0,  # Would need more detailed parsing
                            uncovered_lines=uncovered_lines,
                            file_path=filename
                        )

            except Exception as e:
                print(f"Error parsing XML coverage report: {e}")

        # Parse JSON coverage report for additional details
        json_file = Path("coverage.json")
        if json_file.exists():
            try:
                with open(json_file) as f:
                    json_data = json.load(f)

                for filename, file_data in json_data.get("files", {}).items():
                    if filename in coverage_data:
                        # Add branch coverage if available
                        branch_coverage = file_data.get("summary", {}).get("branch_coverage", 0)
                        coverage_data[filename].branch_coverage_percentage = branch_coverage

            except Exception as e:
                print(f"Error parsing JSON coverage report: {e}")

        return coverage_data

    def generate_coverage_report(self, coverage_data: dict[str, CoverageMetrics]) -> str:
        """Generate a detailed coverage report."""
        if not coverage_data:
            return "No coverage data available."

        report_lines = [
            "# Test Coverage Report",
            "",
            "## Overall Coverage Summary",
            ""
        ]

        # Calculate overall metrics
        total_statements = sum(m.total_statements for m in coverage_data.values())
        total_covered = sum(m.covered_statements for m in coverage_data.values())
        overall_coverage = (total_covered / total_statements * 100) if total_statements > 0 else 0

        report_lines.extend([
            f"- **Total Statements**: {total_statements}",
            f"- **Covered Statements**: {total_covered}",
            f"- **Overall Coverage**: {overall_coverage:.1f}%",
            f"- **Coverage Threshold**: {self.coverage_threshold}%",
            f"- **Status**: {'✅ PASS' if overall_coverage >= self.coverage_threshold else '❌ FAIL'}",
            "",
            "## File-by-File Coverage",
            ""
        ])

        # Sort files by coverage percentage
        sorted_files = sorted(
            coverage_data.items(),
            key=lambda x: x[1].coverage_percentage,
            reverse=True
        )

        for filename, metrics in sorted_files:
            status = "✅" if metrics.coverage_percentage >= self.coverage_threshold else "❌"
            report_lines.append(
                f"- {status} **{filename}**: {metrics.coverage_percentage:.1f}% "
                f"({metrics.covered_statements}/{metrics.total_statements})"
            )

        # Files needing attention
        low_coverage_files = [
            (filename, metrics) for filename, metrics in coverage_data.items()
            if metrics.coverage_percentage < self.coverage_threshold
        ]

        if low_coverage_files:
            report_lines.extend([
                "",
                "## Files Needing Attention",
                ""
            ])

            for filename, metrics in low_coverage_files:
                report_lines.extend([
                    f"### {filename}",
                    f"- Coverage: {metrics.coverage_percentage:.1f}%",
                    f"- Missing lines: {len(metrics.uncovered_lines)}",
                    f"- Uncovered lines: {', '.join(map(str, metrics.uncovered_lines[:10]))}{'...' if len(metrics.uncovered_lines) > 10 else ''}",
                    ""
                ])

        return "\n".join(report_lines)


class QualityAnalyzer:
    """Analyze code quality metrics and patterns."""

    def __init__(self, source_dir: Path = None, test_dir: Path = None):
        self.source_dir = source_dir or Path("vpn")
        self.test_dir = test_dir or Path("tests")

    def analyze_quality(self) -> QualityMetrics:
        """Analyze code quality metrics."""
        # Count files and lines
        source_files = list(self.source_dir.rglob("*.py"))
        test_files = list(self.test_dir.rglob("*.py"))

        total_files = len(source_files)
        test_files_count = len(test_files)

        total_lines = sum(self._count_lines(f) for f in source_files)
        test_lines = sum(self._count_lines(f) for f in test_files)

        # Analyze complexity
        complexity_score = self._analyze_complexity(source_files)

        # Analyze documentation coverage
        doc_coverage = self._analyze_documentation_coverage(source_files)

        # Analyze type annotation coverage
        type_coverage = self._analyze_type_annotations(source_files)

        return QualityMetrics(
            total_files=total_files,
            total_lines=total_lines,
            test_files=test_files_count,
            test_lines=test_lines,
            complexity_score=complexity_score,
            documentation_coverage=doc_coverage,
            type_annotation_coverage=type_coverage
        )

    def _count_lines(self, file_path: Path) -> int:
        """Count non-empty lines in a Python file."""
        try:
            with open(file_path, encoding='utf-8') as f:
                return len([line for line in f if line.strip()])
        except Exception:
            return 0

    def _analyze_complexity(self, files: list[Path]) -> float:
        """Analyze code complexity (simplified McCabe complexity)."""
        total_complexity = 0
        total_functions = 0

        for file_path in files:
            try:
                with open(file_path, encoding='utf-8') as f:
                    tree = ast.parse(f.read())

                for node in ast.walk(tree):
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        complexity = self._calculate_function_complexity(node)
                        total_complexity += complexity
                        total_functions += 1

            except Exception:
                continue

        return total_complexity / total_functions if total_functions > 0 else 0

    def _calculate_function_complexity(self, func_node: ast.AST) -> int:
        """Calculate cyclomatic complexity for a function."""
        complexity = 1  # Base complexity

        for node in ast.walk(func_node):
            if isinstance(node, (ast.If, ast.While, ast.For, ast.AsyncFor)) or isinstance(node, ast.ExceptHandler) or isinstance(node, (ast.ListComp, ast.DictComp, ast.SetComp)):
                complexity += 1

        return complexity

    def _analyze_documentation_coverage(self, files: list[Path]) -> float:
        """Analyze documentation coverage (docstrings)."""
        total_functions = 0
        documented_functions = 0

        for file_path in files:
            try:
                with open(file_path, encoding='utf-8') as f:
                    tree = ast.parse(f.read())

                for node in ast.walk(tree):
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                        total_functions += 1
                        if ast.get_docstring(node):
                            documented_functions += 1

            except Exception:
                continue

        return (documented_functions / total_functions * 100) if total_functions > 0 else 0

    def _analyze_type_annotations(self, files: list[Path]) -> float:
        """Analyze type annotation coverage."""
        total_functions = 0
        annotated_functions = 0

        for file_path in files:
            try:
                with open(file_path, encoding='utf-8') as f:
                    tree = ast.parse(f.read())

                for node in ast.walk(tree):
                    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                        total_functions += 1

                        # Check if function has return annotation
                        has_return_annotation = node.returns is not None

                        # Check if arguments have annotations
                        has_arg_annotations = any(
                            arg.annotation is not None
                            for arg in node.args.args
                        )

                        if has_return_annotation or has_arg_annotations:
                            annotated_functions += 1

            except Exception:
                continue

        return (annotated_functions / total_functions * 100) if total_functions > 0 else 0


class QualityGates:
    """Implement quality gates for automated quality assurance."""

    def __init__(self):
        self.gates = {
            "coverage_threshold": 80.0,
            "branch_coverage_threshold": 70.0,
            "max_complexity": 10.0,
            "min_documentation_coverage": 70.0,
            "min_type_annotation_coverage": 60.0,
            "max_test_to_code_ratio": 2.0,
            "min_test_to_code_ratio": 0.5
        }

    def evaluate_quality(
        self,
        coverage_data: dict[str, CoverageMetrics],
        quality_metrics: QualityMetrics
    ) -> TestQualityReport:
        """Evaluate overall quality against defined gates."""
        violations = []
        recommendations = []
        gates_passed = True

        # Calculate overall coverage
        total_statements = sum(m.total_statements for m in coverage_data.values())
        total_covered = sum(m.covered_statements for m in coverage_data.values())
        overall_coverage = (total_covered / total_statements * 100) if total_statements > 0 else 0

        # Evaluate coverage gates
        if overall_coverage < self.gates["coverage_threshold"]:
            violations.append(
                f"Overall coverage ({overall_coverage:.1f}%) below threshold ({self.gates['coverage_threshold']}%)"
            )
            gates_passed = False

        # Check individual file coverage
        low_coverage_files = [
            filename for filename, metrics in coverage_data.items()
            if metrics.coverage_percentage < self.gates["coverage_threshold"]
        ]

        if low_coverage_files:
            violations.append(
                f"{len(low_coverage_files)} files below coverage threshold: {', '.join(low_coverage_files[:5])}"
            )
            recommendations.append(
                "Add tests for files with low coverage to improve overall quality"
            )

        # Evaluate complexity
        if quality_metrics.complexity_score > self.gates["max_complexity"]:
            violations.append(
                f"Average complexity ({quality_metrics.complexity_score:.1f}) exceeds maximum ({self.gates['max_complexity']})"
            )
            recommendations.append(
                "Refactor complex functions to reduce cyclomatic complexity"
            )
            gates_passed = False

        # Evaluate documentation coverage
        if quality_metrics.documentation_coverage < self.gates["min_documentation_coverage"]:
            violations.append(
                f"Documentation coverage ({quality_metrics.documentation_coverage:.1f}%) below minimum ({self.gates['min_documentation_coverage']}%)"
            )
            recommendations.append(
                "Add docstrings to functions and classes to improve documentation coverage"
            )

        # Evaluate type annotation coverage
        if quality_metrics.type_annotation_coverage < self.gates["min_type_annotation_coverage"]:
            violations.append(
                f"Type annotation coverage ({quality_metrics.type_annotation_coverage:.1f}%) below minimum ({self.gates['min_type_annotation_coverage']}%)"
            )
            recommendations.append(
                "Add type annotations to improve code clarity and tooling support"
            )

        # Evaluate test-to-code ratio
        test_to_code_ratio = quality_metrics.test_lines / quality_metrics.total_lines if quality_metrics.total_lines > 0 else 0

        if test_to_code_ratio < self.gates["min_test_to_code_ratio"]:
            violations.append(
                f"Test-to-code ratio ({test_to_code_ratio:.2f}) below minimum ({self.gates['min_test_to_code_ratio']})"
            )
            recommendations.append(
                "Increase test coverage by adding more comprehensive tests"
            )
            gates_passed = False
        elif test_to_code_ratio > self.gates["max_test_to_code_ratio"]:
            recommendations.append(
                f"Test-to-code ratio ({test_to_code_ratio:.2f}) is very high - ensure tests are efficient"
            )

        # Calculate overall score
        score_components = [
            min(overall_coverage / self.gates["coverage_threshold"], 1.0) * 40,  # 40% weight
            min(self.gates["max_complexity"] / max(quality_metrics.complexity_score, 1), 1.0) * 20,  # 20% weight
            min(quality_metrics.documentation_coverage / self.gates["min_documentation_coverage"], 1.0) * 20,  # 20% weight
            min(quality_metrics.type_annotation_coverage / self.gates["min_type_annotation_coverage"], 1.0) * 20,  # 20% weight
        ]

        overall_score = sum(score_components)

        return TestQualityReport(
            coverage_metrics=coverage_data,
            quality_metrics=quality_metrics,
            quality_gates_passed=gates_passed,
            violations=violations,
            recommendations=recommendations,
            overall_score=overall_score
        )

    def generate_quality_report(self, report: TestQualityReport) -> str:
        """Generate a comprehensive quality report."""
        lines = [
            "# Test Quality Report",
            "",
            f"**Overall Score**: {report.overall_score:.1f}/100",
            f"**Quality Gates**: {'✅ PASSED' if report.quality_gates_passed else '❌ FAILED'}",
            "",
            "## Quality Metrics Summary",
            "",
            f"- **Total Files**: {report.quality_metrics.total_files}",
            f"- **Total Lines**: {report.quality_metrics.total_lines}",
            f"- **Test Files**: {report.quality_metrics.test_files}",
            f"- **Test Lines**: {report.quality_metrics.test_lines}",
            f"- **Test-to-Code Ratio**: {report.quality_metrics.test_lines / report.quality_metrics.total_lines:.2f}",
            f"- **Average Complexity**: {report.quality_metrics.complexity_score:.1f}",
            f"- **Documentation Coverage**: {report.quality_metrics.documentation_coverage:.1f}%",
            f"- **Type Annotation Coverage**: {report.quality_metrics.type_annotation_coverage:.1f}%",
            ""
        ]

        # Add violations section
        if report.violations:
            lines.extend([
                "## ❌ Quality Gate Violations",
                ""
            ])

            for violation in report.violations:
                lines.append(f"- {violation}")

            lines.append("")

        # Add recommendations section
        if report.recommendations:
            lines.extend([
                "## 💡 Recommendations",
                ""
            ])

            for recommendation in report.recommendations:
                lines.append(f"- {recommendation}")

            lines.append("")

        # Add coverage details
        if report.coverage_metrics:
            lines.extend([
                "## 📊 Coverage Details",
                ""
            ])

            total_statements = sum(m.total_statements for m in report.coverage_metrics.values())
            total_covered = sum(m.covered_statements for m in report.coverage_metrics.values())
            overall_coverage = (total_covered / total_statements * 100) if total_statements > 0 else 0

            lines.extend([
                f"**Overall Coverage**: {overall_coverage:.1f}%",
                f"**Total Statements**: {total_statements}",
                f"**Covered Statements**: {total_covered}",
                ""
            ])

        return "\n".join(lines)


# Pytest integration
@pytest.mark.quality
def test_coverage_gates():
    """Test that coverage meets quality gates."""
    analyzer = CoverageAnalyzer()
    coverage_data = analyzer.analyze_coverage()

    if not coverage_data:
        pytest.skip("No coverage data available")

    # Calculate overall coverage
    total_statements = sum(m.total_statements for m in coverage_data.values())
    total_covered = sum(m.covered_statements for m in coverage_data.values())
    overall_coverage = (total_covered / total_statements * 100) if total_statements > 0 else 0

    assert overall_coverage >= analyzer.coverage_threshold, \
        f"Coverage {overall_coverage:.1f}% below threshold {analyzer.coverage_threshold}%"


@pytest.mark.quality
def test_quality_gates():
    """Test that code quality meets defined gates."""
    coverage_analyzer = CoverageAnalyzer()
    quality_analyzer = QualityAnalyzer()
    gates = QualityGates()

    # Analyze coverage and quality
    coverage_data = coverage_analyzer.analyze_coverage()
    quality_metrics = quality_analyzer.analyze_quality()

    # Evaluate against quality gates
    report = gates.evaluate_quality(coverage_data, quality_metrics)

    # Generate report for debugging
    quality_report = gates.generate_quality_report(report)
    print(f"\n{quality_report}")

    # Assert quality gates pass
    assert report.quality_gates_passed, \
        f"Quality gates failed. Violations: {', '.join(report.violations)}"


@pytest.mark.quality
def test_generate_quality_dashboard():
    """Generate a comprehensive quality dashboard."""
    coverage_analyzer = CoverageAnalyzer()
    quality_analyzer = QualityAnalyzer()
    gates = QualityGates()

    # Analyze all metrics
    coverage_data = coverage_analyzer.analyze_coverage()
    quality_metrics = quality_analyzer.analyze_quality()
    report = gates.evaluate_quality(coverage_data, quality_metrics)

    # Generate reports
    coverage_report = coverage_analyzer.generate_coverage_report(coverage_data)
    quality_report = gates.generate_quality_report(report)

    # Save reports to files
    reports_dir = Path("reports")
    reports_dir.mkdir(exist_ok=True)

    (reports_dir / "coverage_report.md").write_text(coverage_report)
    (reports_dir / "quality_report.md").write_text(quality_report)

    # Export metrics as JSON for CI/CD integration
    metrics_json = {
        "overall_score": report.overall_score,
        "quality_gates_passed": report.quality_gates_passed,
        "coverage_percentage": sum(m.covered_statements for m in coverage_data.values()) / sum(m.total_statements for m in coverage_data.values()) * 100 if coverage_data else 0,
        "violations_count": len(report.violations),
        "recommendations_count": len(report.recommendations),
        "complexity_score": quality_metrics.complexity_score,
        "documentation_coverage": quality_metrics.documentation_coverage,
        "type_annotation_coverage": quality_metrics.type_annotation_coverage
    }

    (reports_dir / "quality_metrics.json").write_text(
        json.dumps(metrics_json, indent=2)
    )

    print(f"Quality dashboard generated in {reports_dir}")
    print(f"Overall quality score: {report.overall_score:.1f}/100")


if __name__ == "__main__":
    # Run quality analysis standalone
    test_generate_quality_dashboard()
