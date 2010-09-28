require 'remix/stash'

class Remix::Stash
  # Remix::Stash API doesn't let you set servers
  def self.set_clusters(hash)
    @@clusters = hash
  end
end
