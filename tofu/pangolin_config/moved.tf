# Key migration for pangolin_resource_rule.block_country.
#
# The key used to be "${id}-${name}", but the id is unknown at plan time for a
# resource this configuration has not created yet, and for_each keys must be
# known. The key is now the name alone.
#
# Every other moved block of this configuration was applied and removed. This
# one is left: spliit is no longer declared, so neither address is in the state
# and the block is a no-op.

moved {
  from = pangolin_resource_rule.block_country["12-00NTF - spliit"]
  to   = pangolin_resource_rule.block_country["00NTF - spliit"]
}
