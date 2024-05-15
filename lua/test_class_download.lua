local class = require 'pl.class'
local TestClass = require 'test_class'
local TestClassDownload = class(TestClass)


function TestClassDownload:_init(strTestName, uiTestCase, tLogWriter, strLogLevel)
  self:super(strTestName, uiTestCase, tLogWriter, strLogLevel)

  self.lcurl = require 'lcurl'
  self.mhash = require 'mhash'

  local P = self.P
  self:__parameter {
    P:P('url', 'The url to download.'):
      required(true),

    P:P('url_hash', 'The url of the hash file. The default is the url parameter with a ".sha384" suffix.'):
      required(false),

    P:P('working_folder', 'The working folder for temporary and downloaded files.'):
      required(true),

    P:P('file', 'The absolute path to the downloaded file.'):
      output(true),

    P:P('file_sha384', 'The SHA384 sum of the downloaded file.'):
      output(true),

    P:U32('file_size', 'The size of the downloaded file in bytes.'):
      output(true)
  }
end



function TestClassDownload:__create_working_folder_if_not_present(strWorkingFolder)
  local pl = self.pl
  local tLog = self.tLog

  -- Make an absolute path.
  strWorkingFolder = pl.path.abspath(strWorkingFolder)

  -- Create the working folder if it does not exist.
  if pl.path.exists(strWorkingFolder)==strWorkingFolder then
    tLog.debug('The working folder "%s" exists.', strWorkingFolder)
    if pl.path.isdir(strWorkingFolder)~=true then
      local strMsg = string.format(
        'The working path for the download contents "%s" exists, but it is not a folder.',
        strWorkingFolder
      )
      tLog.error('%s', strMsg)
      error(strMsg)
    end
  else
    -- Try to create the working folder.
    tLog.debug('The working folder "%s" does not exist. Try to create it.', strWorkingFolder)
    local tResult, strMessage = pl.dir.makepath(strWorkingFolder)
    if tResult~=true then
      local strMsg = string.format(
        'Failed to create the working path for the download contents "%s": %s',
        strWorkingFolder,
        tostring(strMessage)
      )
      tLog.error('%s', strMsg)
      error(strMsg)
    end
  end

  return strWorkingFolder
end



function TestClassDownload:__remove_all_files_except_list(strWorkingFolder, astrDoNotDelete)
  local pl = self.pl
  local tLog = self.tLog

  tLog.debug('Clearing the folder "%s" except...', strWorkingFolder)
  for _, strException in ipairs(astrDoNotDelete) do
    tLog.debug('  %s', strException)
  end

  for strPath, fIsDir in pl.dir.dirtree(strWorkingFolder) do
    if pl.tablex.find(astrDoNotDelete, strPath)==nil and fIsDir==false then
      tLog.debug('Removing unknown file "%s"...', strPath)
      pl.file.delete(strPath)
    end
  end
end



function TestClassDownload:__curl_progress(ulDlTotal, ulDlNow)
  local tLog = self.tLog
  local tNow = os.time()
  if os.difftime(tNow, self.tLastProgressTime)>3 then
    if ulDlTotal==0 then
      tLog.info('%d/unknown', ulDlNow)
    else
      tLog.info('%d%% (%d/%d)', math.floor(ulDlNow/ulDlTotal*100), ulDlNow, ulDlTotal)
    end
    self.tLastProgressTime = tNow
  end
  return true
end



function TestClassDownload:__download(strUrl, strLocalFile)
  local tLog = self.tLog

  local lcurl = self.lcurl
  local tCurl = lcurl.easy()

  tCurl:setopt_url(strUrl)

  -- Collect the received data in a file.
  local tFile, strMessage = io.open(strLocalFile, 'wb')
  if tFile==nil then
    local strMsg = string.format(
      'Failed to download the URL "%s": the local file "%s" can not be created: %s',
      strUrl,
      strLocalFile,
      strMessage
    )
    tLog.error('%s', strMsg)
    error(strMsg)
  end

  self.tLastProgressTime = 0
  tCurl:setopt(lcurl.OPT_FOLLOWLOCATION, true)
  tCurl:setopt_writefunction(tFile.write, tFile)
  tCurl:setopt_noprogress(false)
  tCurl:setopt_progressfunction(self.__curl_progress, self)

  local tCallResult, strError = pcall(tCurl.perform, tCurl)
  tFile:close()
  if tCallResult~=true then
    local strMsg = string.format('Failed to retrieve URL "%s": %s', strUrl, strError)
    tLog.error('%s', strMsg)
    error(strMsg)
  else
    local uiHttpResult = tCurl:getinfo(lcurl.INFO_RESPONSE_CODE)
    if uiHttpResult~=200 then
      local strMsg = string.format('Error downloading URL "%s": HTTP response %s', strUrl, tostring(uiHttpResult))
      tLog.error('%s', strMsg)
      error(strMsg)
    end
  end
  tCurl:close()
end



function TestClassDownload:__check_hash_sum(strLocalFile, strLocalFileHash)
  local mhash = self.mhash
  local pl = self.pl
  local tResult
  local strMessage

  -- Check that both files exist.
  if pl.path.exists(strLocalFile)~=strLocalFile then
    strMessage = string.format('The downloaded file "%s" does not exist.', strLocalFile)
  elseif pl.path.isfile(strLocalFile)~=true then
    strMessage = string.format('The downloaded file "%s" is not a file.', strLocalFile)
  elseif pl.path.exists(strLocalFileHash)~=strLocalFileHash then
    strMessage = string.format('The downloaded file "%s" does not exist.', strLocalFileHash)
  elseif pl.path.isfile(strLocalFileHash)~=true then
    strMessage = string.format('The downloaded file "%s" is not a file.', strLocalFileHash)
  else
    -- Read the hash file.
    local strHashData, strError = pl.utils.readfile(strLocalFileHash, false)
    if strHashData==nil then
      strMessage = string.format('Failed to read the local hash file "%s": %s', strLocalFileHash, tostring(strError))
    else
      -- Extract the file name and the hash.
      local strHashCheckHex, strFileCheck = string.match(pl.stringx.strip(strHashData), '^(%x+)%s+(.+)$')
      if strHashCheckHex==nil then
        strMessage = string.format('The hash file "%s" has an invalid format.', strLocalFileHash)
      else
        local strBasename = pl.path.basename(strLocalFile)
        if strFileCheck~=strBasename then
          strMessage = string.format(
            'The hash file does not contain a hash for the file "%s", but for "%s".',
            strBasename,
            strFileCheck
          )
        else
          local tState = mhash.mhash_state()
          tState:init(mhash.MHASH_SHA384)
          -- Open the file and read it in chunks.
          local tFile, strFileError = io.open(strLocalFile, 'rb')
          if tFile==nil then
            strMessage = string.format('Failed to open the file "%s" for reading: %s', strLocalFile, strFileError)
          else
            repeat
              local tChunk = tFile:read(16384)
              if tChunk~=nil then
                tState:hash(tChunk)
              end
            until tChunk==nil
            tFile:close()

            -- Get the binary hash.
            local strHashBin = tState:hash_end()

            -- Convert the binary hash into a string.
            local aHashHex = {}
            for iCnt=1,string.len(strHashBin) do
              table.insert(aHashHex, string.format("%02x", string.byte(strHashBin, iCnt)))
            end
            local strHashHex = table.concat(aHashHex)

            if strHashHex~=strHashCheckHex then
              strMessage = string.format('The hash for the downloaded file "%s" does not match.', strLocalFile)
            else
              tResult = true
              strMessage = strHashHex
            end
          end
        end
      end
    end
  end

  return tResult, strMessage
end



function TestClassDownload:run()
  local atParameter = self.atParameter
  local pl = self.pl
  local tLog = self.tLog

  ----------------------------------------------------------------------
  --
  -- Parse the parameters and collect all options.
  --
  local strParameterUrl = atParameter['url']:get()
  local strParameterUrlHash = atParameter['url_hash']:get()
  local strParameterWorkingFolder = atParameter['working_folder']:get()

  -- Set the default URL hash if none was specified.
  if strParameterUrlHash==nil or strParameterUrlHash=='' then
    strParameterUrlHash = strParameterUrl .. '.sha384'
  end

  -- Create the working folder if it does not exist.
  local strWorkingFolder = self:__create_working_folder_if_not_present(strParameterWorkingFolder)

  -- Extract the file part from the URL.
  local strLocalFile = pl.path.join(strWorkingFolder, pl.path.basename(strParameterUrl))
  local strLocalFileHash = pl.path.join(strWorkingFolder, pl.path.basename(strParameterUrlHash))

  -- Remove everything in the working folder except the URL and URL hash.
  self:__remove_all_files_except_list(strWorkingFolder, { strLocalFile, strLocalFileHash })

  -- If the local file and hash already exist, check the hash sum.
  local strHash
  if pl.path.exists(strLocalFile)==strLocalFile and pl.path.exists(strLocalFileHash)==strLocalFileHash then
    local tResult, strMessage = self:__check_hash_sum(strLocalFile, strLocalFileHash)
    if tResult==true then
      strHash = strMessage
    else
      -- The hash sum does not match. Remove both files.
      tLog.debug('The local file "%s" already exist, but checking the hash failed: %s', strLocalFile, strMessage)

      tResult, strMessage = pl.file.delete(strLocalFile)
      if tResult~=true then
        local strMsg = string.format('Failed to delete the local file "%s": %s', strLocalFile, strMessage)
        tLog.error('%s', strMsg)
        error(strMsg)
      end
      tResult, strMessage = pl.file.delete(strLocalFileHash)
      if tResult~=true then
        local strMsg = string.format('Failed to delete the local file "%s": %s', strLocalFileHash, strMessage)
        tLog.error('%s', strMsg)
        error(strMsg)
      end
    end
  end

  -- Download the URL and the SHA file.
  if pl.path.exists(strLocalFile)~=strLocalFile or pl.path.exists(strLocalFileHash)~=strLocalFileHash then
    self:__download(strParameterUrl, strLocalFile)
    self:__download(strParameterUrlHash, strLocalFileHash)

    -- Check the hash sum of the file.
    local tResult, strMessage = self:__check_hash_sum(strLocalFile, strLocalFileHash)
    if tResult==true then
      strHash = strMessage
    else
      local strMsg = string.format('Checking the hash for the local file "%s" failed: %s.', strLocalFile, strMessage)
      tLog.error('%s', strMsg)

      pl.file.delete(strLocalFile)
      pl.file.delete(strLocalFileHash)

      error(strMsg)
    end
  end

  atParameter['file']:set(strLocalFile)
  atParameter['file_sha384']:set(strHash)
  atParameter['file_size']:set(pl.path.attrib(strLocalFile).size)

  tLog.info("")
  tLog.info(" #######  ##    ## ")
  tLog.info("##     ## ##   ##  ")
  tLog.info("##     ## ##  ##   ")
  tLog.info("##     ## #####    ")
  tLog.info("##     ## ##  ##   ")
  tLog.info("##     ## ##   ##  ")
  tLog.info(" #######  ##    ## ")
  tLog.info("")
end


return TestClassDownload
