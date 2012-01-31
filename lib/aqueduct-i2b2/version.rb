module Aqueduct
  module I2b2
    module VERSION
      MAJOR = 0
      MINOR = 0
      TINY = 0
      BUILD = nil # nil, "pre", "rc", "rc2"

      STRING = [MAJOR, MINOR, TINY, BUILD].compact.join('.')
    end
  end
end
