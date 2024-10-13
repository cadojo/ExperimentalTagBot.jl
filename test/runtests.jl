using GitHub
using ExperimentalTagBot

auth = authenticate(readchomp(`gh auth token`))
proj = project("GeneralAstrodynamics")

