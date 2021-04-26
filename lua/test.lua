local TestClassDownload = require 'test_class_download'
return function(ulTestID, tLogWriter, strLogLevel) return TestClassDownload('Download', ulTestID, tLogWriter, strLogLevel) end
