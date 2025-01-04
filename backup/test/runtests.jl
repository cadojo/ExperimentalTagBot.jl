using Test
using ExperimentalTagBot

# TODO remove @test_throws when (if) this package is registered 
@test_throws ErrorException begin
    vs = ExperimentalTagBot.untagged_versions("ExperimentalTagBot")
    @test isempty(vs)
end