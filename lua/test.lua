local TestClassDownload = require 'test_class_download'
return function(ulTestID, tLogWriter, strLogLevel) return TestClassDownload('@NAME@', ulTestID, tLogWriter, strLogLevel) end
