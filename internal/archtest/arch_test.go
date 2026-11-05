// Package archtest enforces the Elm rules of ux-spec §2.1 (setup-tui) on the pure packages:
// no I/O imports, no clock reads, no hand-written colors, no hard-coded component ids (C2).
package archtest

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

const module = "github.com/Robertcl795/umbra-bootstrapper/"

var pure = []string{"internal/catalog", "internal/plan", "internal/events", "internal/sys", "internal/msgs",
	"internal/theme", "internal/i18n", "internal/ui", "internal/screens", "internal/app"}

var banned = map[string]bool{"os": true, "os/exec": true, "io/fs": true, "io/ioutil": true,
	"net": true, "net/http": true, "syscall": true}

func root() string { return filepath.Join("..", "..") }

func goFiles(t *testing.T, dir string) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(root(), dir, "*.go"))
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, f := range files {
		if !strings.HasSuffix(f, "_test.go") {
			out = append(out, f)
		}
	}
	return out
}

func TestPurePackagesDoNotImportIO(t *testing.T) {
	for _, p := range pure {
		out, err := exec.Command("go", "list", "-f", `{{join .Imports " "}}`, module+p).Output()
		if err != nil {
			t.Fatalf("go list %s: %v", p, err)
		}
		for _, imp := range strings.Fields(string(out)) {
			if banned[imp] {
				t.Errorf("%s imports %s (side effects belong in internal/effects)", p, imp)
			}
		}
	}
}

func TestPurePackagesDoNotReadTheClock(t *testing.T) {
	for _, p := range pure {
		for _, f := range goFiles(t, p) {
			file, err := parser.ParseFile(token.NewFileSet(), f, nil, 0)
			if err != nil {
				t.Fatal(err)
			}
			ast.Inspect(file, func(n ast.Node) bool {
				if s, ok := n.(*ast.SelectorExpr); ok {
					if id, ok := s.X.(*ast.Ident); ok && id.Name == "time" && (s.Sel.Name == "Now" || s.Sel.Name == "Since") {
						t.Errorf("%s calls time.%s (inject the clock through effects.Env)", f, s.Sel.Name)
					}
				}
				return true
			})
		}
	}
}

// Every Go file outside tokens_gen.go is free of color literals (contract C4).
func TestNoHexOutsideGeneratedTokens(t *testing.T) {
	hex := regexp.MustCompile(`#[0-9A-Fa-f]{6}\b`)
	_ = filepath.Walk(root(), func(p string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(p, ".go") || strings.HasSuffix(p, "tokens_gen.go") {
			return nil
		}
		b, _ := os.ReadFile(p)
		if m := hex.Find(b); m != nil {
			t.Errorf("%s holds a color literal %s (read it from internal/theme)", p, m)
		}
		return nil
	})
}

// No component id is written in non-test Go code: the catalog is the only list (contract C2).
func TestNoComponentIDsInGo(t *testing.T) {
	b, err := os.ReadFile(filepath.Join(root(), "env", "wsl", "install", "components.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	ids := map[string]bool{}
	for _, line := range strings.Split(string(b), "\n") {
		if id, _, ok := strings.Cut(line, "\t"); ok && id != "id" && !strings.HasPrefix(id, "#") {
			ids[id] = true
		}
	}
	_ = filepath.Walk(filepath.Join(root(), "internal"), func(p string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || !strings.HasSuffix(p, ".go") || strings.HasSuffix(p, "_test.go") {
			return nil
		}
		file, err := parser.ParseFile(token.NewFileSet(), p, nil, 0)
		if err != nil {
			t.Fatal(err)
		}
		ast.Inspect(file, func(n ast.Node) bool {
			if lit, ok := n.(*ast.BasicLit); ok && lit.Kind == token.STRING {
				s, err := strconv.Unquote(lit.Value)
				// Allowed: plan.k8sComponent, named by bootstrap.sh's own --enable-k8s flag.
				allowed := s == "k8s" && strings.HasSuffix(p, filepath.Join("plan", "plan.go"))
				if err == nil && ids[s] && !allowed {
					t.Errorf("%s: component id %q is hard-coded (read it from the catalog)", p, s)
				}
			}
			return true
		})
		return nil
	})
}

// Elm rule E3: the TUI packages keep no mutable package state. A package var may only hold a
// table of literals (menu order, glyphs); anything else belongs in the model.
func TestTUIHasNoPackageState(t *testing.T) {
	for _, dir := range []string{"internal/app", "internal/screens", "internal/ui", "internal/msgs", "internal/sys"} {
		for _, f := range goFiles(t, dir) {
			file, err := parser.ParseFile(token.NewFileSet(), f, nil, 0)
			if err != nil {
				t.Fatal(err)
			}
			for _, d := range file.Decls {
				g, ok := d.(*ast.GenDecl)
				if !ok || g.Tok != token.VAR {
					continue
				}
				for _, sp := range g.Specs {
					v := sp.(*ast.ValueSpec)
					if len(v.Values) == 0 || !literalTable(v.Values[0]) {
						t.Errorf("%s: package variable %s is not a literal table (keep state in the model)", f, v.Names[0])
					}
				}
			}
		}
	}
}

func literalTable(e ast.Expr) bool {
	switch x := e.(type) {
	case *ast.BasicLit:
		return true
	case *ast.CompositeLit:
		for _, el := range x.Elts {
			if kv, ok := el.(*ast.KeyValueExpr); ok {
				el = kv.Value
			}
			if !literalTable(el) {
				return false
			}
		}
		return true
	}
	return false
}
