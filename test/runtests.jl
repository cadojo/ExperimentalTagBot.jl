import GitHub as GH
import ExperimentalTagBot

auth = GH.authenticate(readchomp(`gh auth token`))
ExperimentalTagBot.create_releases("GeneralAstrodynamics"; auth = auth)