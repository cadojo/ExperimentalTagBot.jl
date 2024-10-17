using Revise
import GitHub as GH
using ExperimentalTagBot

auth = GH.authenticate(readchomp(`gh auth token`))
package = "GeneralAstrodynamics"
proj = project(package)
