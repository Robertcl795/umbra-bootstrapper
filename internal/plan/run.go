package plan

import (
	"slices"
	"sort"
	"strings"

	"github.com/Robertcl795/umbra-bootstrapper/internal/catalog"
)

// Doctor is the id of the last phase, run by umbra-setup itself after install.sh (ux-spec §3).
const Doctor = "doctor"

// Stage1 lists the phases stage1.sh runs as root on WSL, in its order (run_stage1).
var Stage1 = []string{"P0", "P1", "P2", "P3", "P3r"}

// Summary is the chezmoi script every WSL run ends with.
const Summary = "run_onchange_after_99-summary.sh"

// Phases lists the phases a run of these items will report, in chezmoi's order: run_*_before_
// scripts, then run_*_after_, each sorted by name, then the doctor. Ids that start later but
// are not listed here (stage 1, retire-links) are added by the run screen as they arrive.
func Phases(c catalog.Catalog, platform string, items []string) []string {
	var scripts []string
	for _, it := range c.For(platform) {
		if slices.Contains(items, it.ID) {
			for _, s := range it.Scripts {
				if !slices.Contains(scripts, s) {
					scripts = append(scripts, s)
				}
			}
		}
	}
	if strings.HasPrefix(platform, "wsl-") {
		scripts = append(scripts, Summary)
	}
	sort.SliceStable(scripts, func(i, j int) bool {
		a, b := stage(scripts[i]), stage(scripts[j])
		if a != b {
			return a < b
		}
		return scripts[i] < scripts[j]
	})
	return append(scripts, Doctor)
}

func stage(script string) int {
	if strings.Contains(script, "_after_") {
		return 1
	}
	return 0
}

// ItemsFromComponents returns the ids whose components are all in comps (the stored chezmoi
// selection, read back for a re-run), in menu order.
func ItemsFromComponents(c catalog.Catalog, platform string, comps []string) []string {
	var ids []string
	for _, it := range c.For(platform) {
		all := len(it.Components) > 0
		for _, comp := range it.Components {
			if !slices.Contains(comps, comp) {
				all = false
			}
		}
		if all {
			ids = append(ids, it.ID)
		}
	}
	return ids
}

// Short is a phase id as the run screen shows it: "before_30-prompt" for a chezmoi script.
func Short(id string) string {
	id = strings.TrimSuffix(id, ".sh")
	for _, p := range []string{"run_onchange_", "run_once_"} {
		id = strings.TrimPrefix(id, p)
	}
	return id
}

// DoctorEnv is the selection the doctor (tests/99_smoke.sh) needs, as finish.sh has it: without
// UM_COMPONENTS it checks every component, also the ones nobody chose.
func DoctorEnv(c catalog.Catalog, platform string, s Selection) []string {
	comps, _ := Components(c, platform, s.Items)
	env := []string{"UM_COMPONENTS=" + strings.Join(comps, ","), "UM_SKIP=" + strings.Join(s.Skip, ","),
		"UM_SKIP_PACKAGES=" + strings.Join(s.SkipPackages, ","), "UM_MODE=" + s.Profile}
	if s.Shell != "" { // tests/03_shell.sh checks the chosen shell
		env = append(env, "UM_SHELL="+s.Shell)
	}
	return env
}
