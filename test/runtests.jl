using Revise
import GitHub as GH
using ExperimentalTagBot

auth = GH.authenticate(readchomp(`gh auth token`))
package = "GeneralAstrodynamics"
proj = project(package)

prs = ExperimentalTagBot.release_pr(package, "v0.9.2")
ExperimentalTagBot.commit(package, "v0.9.2")