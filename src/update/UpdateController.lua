--
-- Author: TsingZhang@boyaa.com
-- Date: 2017-03-27 16:53:31
-- Copyright: Copyright (c) 2015, BOYAA INTERACTIVE CO., LTD All rights reserved.
-- Description: UpdateController.lua ReConstructed By Tsing7x.
--

log = print

local upd = import(".init")
local UpdateScene = import(".UpdateScene")
local UpdateView = import(".UpdateView")

local UpdateController = class("UpdateController")

function UpdateController:ctor()
    cc.FileUtils:getInstance():addSearchPath(device.writablePath .. "upd/res/")
    cc.FileUtils:getInstance():addSearchPath("res/")

    self:initUpdate()

    self.scene_ = UpdateScene.new(self)
    self.view_ = self.scene_:getUpdateView()
    display.replaceScene(self.scene_)
end

function UpdateController:initUpdate()
    -- log("initUpdate..")
    upd.mkdir(upd.conf.UPDATE_DIR)
    upd.mkdir(upd.conf.UPDATE_RES_DIR)
    upd.mkdir(upd.conf.UPDATE_RES_TMP_DIR)

    if upd.conf.ENABLED and upd.isFileExist(upd.conf.UPDATE_LIST_FILE) then
        self.fileList_ = dofile(upd.conf.UPDATE_LIST_FILE)
    end
    self.fileList_ = self.fileList_ or {ver = upd.conf.CLIENT_VERSION, stage = {}, remove = {}}
    -- log("fileList_:" .. json.encode(self.fileList_))

    local fileCheckOK = true
    -- log("checking local files ..")
    self:checkResources(self.fileList_, function(fileinfo, name)
        if name ~= fileinfo.name then
            if string.find(fileinfo.name, "/") then
                local arr = string.split(fileinfo.name, "/")
                arr[#arr] = nil
                upd.mkdir(upd.conf.UPDATE_RES_DIR .. table.concat(arr, "/") .. "/")
            end

            local oldfile = upd.conf.UPDATE_RES_DIR .. name
            local newfile = upd.conf.UPDATE_RES_DIR .. fileinfo.name
            -- log("rename " .. oldfile .. " => " .. newfile)

            if upd.isFileExist(newfile) then
                os.remove(newfile)
            end

            os.rename(oldfile, newfile)
        end

        fileinfo.fileCheckOK = true
    end, function(file)
        -- log("remove => " .. file)
        os.remove(file)
    end)

    for k, v in pairs(self.fileList_.stage) do
        if not v.fileCheckOK then
            fileCheckOK = false
            -- log("missing file => " .. v.name)
        end
    end

    -- Check Local Resource Not Ok, Remove All --
    if not fileCheckOK then
        -- log("FILE CHECK FAILED!!!")
        upd.rmdir(upd.conf.UPDATE_DIR)
        upd.mkdir(upd.conf.UPDATE_DIR)
        upd.mkdir(upd.conf.UPDATE_RES_DIR)
        upd.mkdir(upd.conf.UPDATE_RES_TMP_DIR)
        self.fileList_ = {ver = upd.conf.CLIENT_VERSION, stage = {}, remove = {}}
    else
        log("local files check ok.")
    end
end

function UpdateController:checkResources(filelist, validMd5Handler, notFoundHandler)
    -- Check Local Not Needed Files --
    local interateDir = nil
    interateDir = function(basepath, path, namebase)
        local iter, dir_obj = lfs.dir(path)
        while true do
            local dir = iter(dir_obj)
            if dir == nil then break end

            if dir ~= "." and dir ~= ".." then
                local curDir = path .. dir
                local mode = lfs.attributes(curDir, "mode")
                local name = namebase and (namebase .. "/" .. dir) or dir

                if mode == "directory" then
                    interateDir(basepath, curDir.."/", name)
                elseif mode == "file" then

                    local md5 = string.lower(crypto.md5file(curDir))
                    local keep = false
                    for i, v in ipairs(filelist.stage) do
                        if string.lower(v.code) == md5 then

                            keep = true
                            if validMd5Handler then
                                validMd5Handler(v, name)
                            end
                            break
                        end
                    end

                    if not keep then
                        if notFoundHandler then
                            notFoundHandler(curDir)
                        end
                    end
                end
            end
        end
    end

    interateDir(upd.conf.UPDATE_RES_DIR, upd.conf.UPDATE_RES_DIR)
end

function UpdateController:startUpdate()
    -- Tips Checking Versions --
    -- log("startUpdate checking server version..")
    self.view_:setVersionInfo(self.fileList_.ver)
    self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "CHECKING_VERSION"))
    self.view_:setUpdateInfoVisible(false)

    if not upd.conf.ENABLED then
        self:endUpdate()
        return
    end

    if upd.is_mobile_platform() then
        local g = global_statistics_for_umeng
        g.umeng_view = g.Views.loading
    end

    local checkFirstApiBegin = 0
    local checkFirstApiEnd = 0
    local g = global_statistics_for_umeng
    local checkFirstApiInfo = g.update_check_info.firstApi

    local retryTimes = 1
    local requestServerVersion = nil
    requestServerVersion = function()
        local params = {
            device = ((device.platform == "windows"  or device.platform == "mac") and upd.TestUtil.simuDevice or device.platform), 
            pay = ((device.platform == "windows"  or device.platform == "mac") and upd.TestUtil.simuDevice or device.platform), 
            noticeVersion = "noticeVersion", osVersion = upd.conf.CLIENT_VERSION, version = upd.conf.CLIENT_VERSION,
            sid = appconfig.ROOT_CGI_SID
        }

        -- dump(params,"version check param org :===============")
        if IS_DEMO then
            params.demo = 1
        end

        if upd.conf.ENABLED and upd.conf.PRE_PUBLIC then
            params.test = 1
        end

        checkFirstApiBegin = os.time()

        -- dump(params,"version check param post :===============")
        upd.http.POST_URL(appconfig.VERSION_CHECK_URL, params, function (data)
            -- log("POST(VERSION_CHECK_URL).jsonData :" .. data)

            checkFirstApiEnd = os.time()
            checkFirstApiInfo[(3 - retryTimes + 1)] = {result = "success", time = (checkFirstApiEnd - checkFirstApiBegin), check = (3 - retryTimes + 1)}
            --{"device":"android","curVersion":"10.0.0","verTitle":null,"verMessage":[""],"isForce":null,"updateUrl":null,"commentUrl":null,
                -- "FEEDBACK_CGI":"http:\/\/mvlptlpd01.boyaagame.com\/androidtl\/api\/feedback.php",
                -- "loginUrl":"http:\/\/mvlptlpd01.boyaagame.com\/androidtl\/platform\/androidtl\/index.php",
                -- "updatePath":"http:\/\/mvlptlpd01-static.boyaagame.com\/update\/androidtl\/"
            -- }
            local retData = data and json.decode(data) or nil
            if retData then
                -- dump(retData, "POST(VERSION_CHECK_URL).retData :==============")

                self.FACEBOOK_BONUS = tonumber(retData.fbBonus)
                local svrVersion = retData.curVersion
                local svrVerTitle = retData.verTitle
                local svrVerMsg = retData.verMessage
                local svrStoreURL = retData.updateUrl
                local svrIsForce = (checknumber(retData.isForce) ~= 0)
                local svrFBBonus = tonumber(retData.fbBonus)
                self.feedBackUrl = retData.FEEDBACK_CGI
                self.loginUrl = retData.loginUrl
                self.commentUrl = retData.commentUrl
                
                upd.conf.SERVER_FILE_URL_FMT =  retData.updatePath .. "%s?dev=" ..
                    ((device.platform == "windows" or device.platform == "mac") and upd.TestUtil.simuDevice or device.platform) .. "&%s"

                if upd.conf.DEBUG then
                    svrVersion = upd.conf.DEBUG_SVR_VERSION or svrVersion
                end
                
                local svrVersionNum = upd.getVersionNum(svrVersion, 3)
                local cliVersionNum = upd.getVersionNum(upd.conf.CLIENT_VERSION, 3)
                local curVersionNum = upd.getVersionNum(self.fileList_.ver, 3)

                -- log("svrVersionNum " .. svrVersionNum)
                -- log("cliVersionNum " .. cliVersionNum)
                -- log("curVersionNum " .. curVersionNum)

                -- Big Version Changes, Remove All Exsited Files --
                if cliVersionNum ~= curVersionNum then
                    -- log("DELETE INVALID UPDATE FILES")
                    upd.rmdir(upd.conf.UPDATE_DIR)
                    upd.mkdir(upd.conf.UPDATE_DIR)
                    upd.mkdir(upd.conf.UPDATE_RES_DIR)
                    upd.mkdir(upd.conf.UPDATE_RES_TMP_DIR)

                    self.fileList_ = {ver = upd.conf.CLIENT_VERSION, stage = {}, remove = {}}
                    curVersionNum = cliVersionNum
                end

                if curVersionNum >= svrVersionNum then
                    -- Not Need Big Version Update, Start Hotupdate --
                    self:startHotUpdate()
                else
                    -- Need Big Version Update, Pop Alert --
                    local count = cc.UserDefault:getInstance():getIntegerForKey(upd.conf.SKIT_UPDATE_TIMES_KEY, 0)
                    device.showAlert(svrVerTitle, svrVerMsg, {upd.lang.getText("UPDATE", "UPDATE_NOW"), upd.lang.getText("UPDATE", "UPDATE_LATER")}, 
                        function(event)
                            if event.buttonIndex == 1 then
                                device.openURL(svrStoreURL)
                            else
                                cc.UserDefault:getInstance():setIntegerForKey(upd.conf.SKIT_UPDATE_TIMES_KEY, count + 1)
                            end

                            if svrIsForce then
                                os.exit()
                            else
                                self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "UPDATE_CANCELED"))
                                self:startHotUpdate()
                            end
                        end
                    )
                end
            else
                checkFirstApiEnd = os.time()
                checkFirstApiInfo[(3 - retryTimes + 1)] = {result = "fail", time = (checkFirstApiEnd - checkFirstApiBegin),
                    check = (3 - retryTimes + 1)}

                retryTimes = retryTimes - 1
                if retryTimes >= 0 then
                    requestServerVersion()
                else
                    self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "BAD_NETWORK_MSG"))
                    self:endUpdate()
                end
            end

        end, function(errData)
            dump(errData, "POST(VERSION_CHECK_URL).errData :==============")
            -- log("retryTimes value :" .. retryTimes)

            retryTimes = retryTimes - 1
            if retryTimes >= 0 then
                requestServerVersion()
            else
                self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "BAD_NETWORK_MSG"))
                self:endUpdate()
            end
        end)
    end
    requestServerVersion()
end

function UpdateController:startHotUpdate()
    -- log("startHotUpdate..")
    self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "CHECKING_RES_UPDATE"))

    local checkFlistBegin = 0
    local checkFlistApiEnd = 0
    local g = global_statistics_for_umeng
    local checkFlistInfo = g.update_check_info.flist
    
    local retryTimes = 2
    local newFileListFile = upd.conf.UPDATE_LIST_FILE .. ".upd"

    local requestServerFileList = nil
    requestServerFileList = function()
        checkFlistBegin = os.time()
        upd.http.GET_URL(string.format(upd.conf.SERVER_FILE_URL_FMT, upd.conf.UPDATE_LIST_FILE_NAME, upd.getTime()), {},
            function(data)

                checkFlistApiEnd = os.time()
                checkFlistInfo[(3 - retryTimes + 1)] = {result = "success", time = (checkFlistApiEnd - checkFlistBegin), check = (3 - retryTimes + 1)}

                -- Write Download Info Into Local Files --
                io.writefile(newFileListFile, data, "wb+")
                self.fileListNew_ = dofile(newFileListFile)

                -- log("fileListNew_:" .. json.encode(self.fileListNew_))
                if not self.fileListNew_ then
                    retryTimes = retryTimes - 1
                    if retryTimes >= 0 then
                        requestServerFileList()
                    else
                        self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "DOWNLOAD_ERROR"))
                        self:endUpdate()
                    end

                    return
                end

                local curVersionNum = upd.getVersionNum(self.fileList_.ver, 4)
                local svrVersionNum = upd.getVersionNum(self.fileListNew_.ver, 4)

                -- log("curVersionNum " .. curVersionNum)
                -- log("svrVersionNum " .. svrVersionNum)

                if curVersionNum >= svrVersionNum then
                    -- log("already latest version")
                    self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "IS_ALREADY_THE_LATEST_VERSION"))
                    self:endUpdate()
                else
                    self:startDownload()
                end
            end, function(data)
                log("hotUpdate Faild ErrorCode :" .. data)

                log("retryTimes :" .. retryTimes)
                if retryTimes ~= 0 and data == 404 then
                    retryTimes = 0
                end

                if retryTimes > 1 and data == 28 then
                    retryTimes = 1
                end

                checkFlistApiEnd = os.time()
                checkFlistInfo[(3 - retryTimes + 1)] = {result = "fail", time = (checkFlistApiEnd - checkFlistBegin), check = (3 - retryTimes + 1)}

                retryTimes = retryTimes - 1
                if retryTimes >= 0 then
                    requestServerFileList()
                else
                    log("retryTimes :" .. retryTimes)
                    self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "DOWNLOAD_ERROR"))
                    self:endUpdate()
                    log("endUpdate done!")
                end
            end
        )
    end
    requestServerFileList()
end

function UpdateController:startDownload()
    -- log("startDownload..")
    -- Req Need DownLoad File List --
    self.downloadList_ = clone(self.fileListNew_.stage)
    self.updateCommands_ = {}
    self.silentUpdateCommands_ = {}

    -- log("checking local resources..")
    -- Check Dir upd Files --
    self:checkResources(self.fileList_, function(fileinfo, name)
        if name ~= fileinfo.name then
            if string.find(fileinfo.name, "/") then
                local arr = string.split(fileinfo.name, "/")
                arr[#arr] = nil
                upd.mkdir(upd.conf.UPDATE_RES_DIR .. table.concat(arr, "/") .. "/")
            end
            local oldfile = upd.conf.UPDATE_RES_DIR .. name
            local newfile = upd.conf.UPDATE_RES_DIR .. fileinfo.name
            table.insert(self.updateCommands_, function()
                -- log("rename " .. oldfile .. " => " .. newfile)
                os.rename(oldfile, newfile)
            end)
        end

        table.filter(self.downloadList_, function(v, k)
            return string.lower(v.code) ~= fileinfo.code
        end)

        -- log("file " .. fileinfo.name .. "(" .. fileinfo.code .. ") already exists")
    end, function(file)
        table.insert(self.updateCommands_, function()
            -- log("remove => " .. file)
            os.remove(file)
        end)
    end)
    
    -- Check Dir updtemp If Exist Same MD5 Code File, Not DownLoad --
    table.filter(self.downloadList_, function(v, k)
        local tmpfile = upd.conf.UPDATE_RES_TMP_DIR .. string.lower(v.code)
        if upd.isFileExist(tmpfile) then
            if string.lower(crypto.md5file(tmpfile)) == string.lower(v.code) then
                if string.find(v.name, "/") then
                    local arr = string.split(v.name, "/")
                    arr[#arr] = nil
                    upd.mkdir(upd.conf.UPDATE_RES_DIR .. table.concat(arr, "/") .. "/")
                end

                table.insert(self.updateCommands_, function()
                    os.rename(upd.conf.UPDATE_RES_TMP_DIR .. string.lower(v.code), upd.conf.UPDATE_RES_DIR .. v.name)
                end)

                -- log("file " .. v.name .. "(" .. v.code .. ") already downloaded to restmp")
                return false
            else
                -- log("remove broken file => " .. tmpfile)
                os.remove(tmpfile)
            end
        end

        return true
    end)

    self.downloadList_ = table.values(self.downloadList_)

    self.downloadSilentList_ = clone(self.downloadList_)
    self.downloadList_ = clone(self.downloadList_)

    --dump(self.downloadSilentList_,"self.downloadSilentList_")

    table.filter(self.downloadSilentList_, function(v, k)
        return ( 1 == tonumber(v.silent))
    end)

     table.filter(self.downloadList_, function(v, k)
        return (1 ~= tonumber(v.silent))
    end)

    self.downloadList_ = table.values(self.downloadList_)
    self.downloadSilentList_ = table.values(self.downloadSilentList_)


    --dump(self.downloadList_,"downloadList_ :======")
    --dump(self.downloadSilentList_,"downloadSilentList_ :=======")

    self.downloadSilentFileSize_ = 0
    if #self.downloadSilentList_ > 0 then
         self.downloadSilentFileNum_ = 0
        for k, v in pairs(self.downloadSilentList_) do
            if v then
                self.downloadSilentFileSize_ = self.downloadSilentFileSize_ + checknumber(v.size)
                self.downloadSilentFileNum_ = self.downloadSilentFileNum_ + 1
            end
        end

        -- log("download silent file size => " .. self.downloadSilentFileSize_ .. "K")
        local downloadSizeLabel
        if self.downloadSilentFileSize_ > 1024 then
            downloadSizeLabel = string.format("%.2fM", self.downloadSilentFileSize_ / 1024)
        else
            downloadSizeLabel = self.downloadSilentFileSize_ .. "K"
        end

        self.downloadSilentFileIndex_ = 1
        self:downloadNextSilentFile()

    else
        dump("No Silent_DownLoad File.")
    end
    
    -- Calc Download File Size --
    self.downloadFileSize_ = 0
    if #self.downloadList_ > 0 then
        self.downloadFileNum_ = 0
        for k, v in pairs(self.downloadList_) do
            if v then
                self.downloadFileSize_ = self.downloadFileSize_ + checknumber(v.size)
                self.downloadFileNum_ = self.downloadFileNum_ + 1
            end
        end

        -- log("download file size => " .. self.downloadFileSize_ .. "K")
        local downloadSizeLabel
        if self.downloadFileSize_ > 1024 then
            downloadSizeLabel = string.format("%.2fM", self.downloadFileSize_ / 1024)
        else
            downloadSizeLabel = self.downloadFileSize_ .. "K"
        end

        self.view_:setDownloadSizeTotalInfo(downloadSizeLabel)

        local netState = network.getInternetConnectionStatus()
        if netState ~= cc.kCCNetworkStatusReachableViaWiFi then
            device.showAlert(upd.lang.getText("UPDATE", "DOWNLOAD_NOT_IN_WIFI_PROMPT_TITLE"),
                upd.lang.getText("UPDATE", "DOWNLOAD_NOT_IN_WIFI_PROMPT_MSG", downloadSizeLabel), {upd.lang.getText("UPDATE", "UPDATE_LATER"),
                    upd.lang.getText("UPDATE", "UPDATE_NOW")}, function(event)

                    if event.buttonIndex == 2 then
                        self.view_:setUpdateInfoVisible(true)
                        self.downloadFileIndex_ = 1
                        self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "DOWNLOADING_MSG", self.downloadFileIndex_, self.downloadFileNum_))
                        self:downloadNextFile()
                    else
                        self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "UPDATE_CANCELED"))
                        self:endUpdate()
                    end
                end
            )
        else
            self.view_:setUpdateInfoVisible(true)
            self.downloadFileIndex_ = 1
            self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "DOWNLOADING_MSG", self.downloadFileIndex_, self.downloadFileNum_))
            self:downloadNextFile()
        end
    else
        self:completeUpdate()
    end
end

function UpdateController:downloadNextFile()
    if #self.downloadList_ > 0 then

        local fileinfo = table.remove(self.downloadList_, 1)
        if not fileinfo then return self:downloadNextFile() end

        local retryTimes = 2
        -- log("downloading ====> " .. fileinfo.name)
        self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "DOWNLOADING_MSG", self.downloadFileIndex_, self.downloadFileNum_))
        
        local requestFile = nil
        requestFile= function()
            local lastTime = upd.getTime()
            local lastSize = 0
            local lastSpeed = "0KB/S"
            local request = nil
            request = network.createHTTPRequest(function(event)
                if event.name == "completed" then
                    -- log("downloadNextFile.retCode :" .. request:getResponseStatusCode())
                    dump(event, "event.completed :=================")
                    if request:getResponseStatusCode() ~= 200 then
                        retryTimes = retryTimes - 1
                        if retryTimes >= 0 then
                            requestFile()
                        else
                            self:endUpdate()
                        end

                        return
                    end

                    local data = request:getResponseData()

                    --dump(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp","loadingSB")

                    io.writefile(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp", data, "wb+")
                    if string.lower(crypto.md5file(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp")) == string.lower(fileinfo.code) then

                        self.view_:setProgress(1, lastSpeed)
                        os.rename(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp", upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code)
                        --dump(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code,"fileinfo.code")
                        if string.find(fileinfo.name, "/") then
                            local arr = string.split(fileinfo.name, "/")
                            arr[#arr] = nil
                            upd.mkdir(upd.conf.UPDATE_RES_DIR .. table.concat(arr, "/") .. "/")
                        end

                        table.insert(self.updateCommands_, function()
                            os.rename(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code, upd.conf.UPDATE_RES_DIR .. fileinfo.name)
                        end)

                        self.downloadFileIndex_ = self.downloadFileIndex_ + 1
                        self:downloadNextFile()
                    else
                        -- log("File MD5 Code Not Match.")
                        self.view_:setProgress(0, lastSpeed)
                        
                        os.remove(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp")
                        retryTimes = retryTimes -1

                        if retryTimes >= 0 then
                            requestFile()
                        else
                            self:endUpdate()
                        end
                    end
                elseif event.name == "progress" then
                    -- dump(event, "event.progress :===============")

                    local now = upd.getTime()
                    if now - lastTime > 1.5 then
                        if event.dltotal > lastSize then

                            lastSpeed = (event.dltotal - lastSize) / ((now - lastTime) * 1024)
                            if lastSpeed > 1024 then
                                lastSpeed = string.format("%.2fMB/S", lastSpeed / 1024)
                            else
                                lastSpeed = string.format("%dKB/S", lastSpeed)
                            end
                        end

                        lastSize = event.dltotal
                        lastTime = now
                    end
                    -- log(string.format("inprogress %s %s %s %s %s", event.total, event.dltotal, event.ultotal, event.ulnow, lastSpeed))
                    self.view_:setProgress(event.total == 0 and 0 or event.dltotal / event.total, lastSpeed)
                else
                    retryTimes = retryTimes -1
                    if retryTimes >= 0 then
                        requestFile()
                    else
                        self:endUpdate()
                    end
                end
            end, string.format(upd.conf.SERVER_FILE_URL_FMT, fileinfo.code, upd.getTime()), "GET")

            request:setTimeout(60 * 10)
            request:start()
        end

        requestFile()
    else
        self:completeUpdate()
    end
end

function UpdateController:downloadNextSilentFile()
    if #self.downloadSilentList_ > 0 then
        local fileinfo = table.remove(self.downloadSilentList_, 1)
        if not fileinfo then return self:downloadNextSilentFile() end
        local requestFile = nil
        local retryTimes = 2

        requestFile = function()
            local lastTime = upd.getTime()
            local lastSize = 0
            local lastSpeed = "0KB/S"
            local request = nil

            request = network.createHTTPRequest(function(event)
                if event.name == "completed" then
                    -- log("DownloadNextSilentFile.retCode :" .. request:getResponseStatusCode())

                    if request:getResponseStatusCode() ~= 200 then
                        retryTimes = retryTimes - 1
                        if retryTimes >= 0 then
                            requestFile()
                        end

                        return
                    end
                    local data = request:getResponseData()
                    io.writefile(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp", data, "wb+")
                    if string.lower(crypto.md5file(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp")) == string.lower(fileinfo.code) then
                        os.rename(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp", upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code)
                        
                        if string.find(fileinfo.name, "/") then
                            local arr = string.split(fileinfo.name, "/")
                            arr[#arr] = nil
                            upd.mkdir(upd.conf.UPDATE_RES_DIR .. table.concat(arr, "/") .. "/")
                        end

                        table.insert(self.silentUpdateCommands_, function()
                            os.rename(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code, upd.conf.UPDATE_RES_DIR .. fileinfo.name)
                        end)

                        self.downloadSilentFileIndex_ = self.downloadSilentFileIndex_ + 1
                        self:downloadNextSilentFile()
                    else
                        -- log("Silent File MD5 Code Not Match.")
                        os.remove(upd.conf.UPDATE_RES_TMP_DIR .. fileinfo.code .. ".tmp")
                        retryTimes = retryTimes -1
                        if retryTimes >= 0 then
                            requestFile()
                        end
                    end
                elseif event.name == "progress" then
                    local now = upd.getTime()
                    if now - lastTime > 1.5 then
                        if event.dltotal > lastSize then
                            lastSpeed = (event.dltotal - lastSize) / ((now - lastTime) * 1024)
                            if lastSpeed > 1024 then
                                lastSpeed = string.format("%.2fMB/S", lastSpeed / 1024)
                            else
                                lastSpeed = string.format("%dKB/S", lastSpeed)
                            end
                        end
                        lastSize = event.dltotal
                        lastTime = now
                    end
                    
                    -- log(string.format("inprogress %s %s %s %s %s", event.total, event.dltotal, event.ultotal, event.ulnow, lastSpeed))
                else
                    retryTimes = retryTimes -1
                    if retryTimes >= 0 then
                        requestFile()
                    end
                end
            end, string.format(upd.conf.SERVER_FILE_URL_FMT, fileinfo.code, upd.getTime()), "GET")
            request:setTimeout(60 * 10)
            request:start()
        end

        requestFile()
    else
        self:completedSilentUpdate()
    end
end

function UpdateController:completeUpdate()
    while #self.updateCommands_ > 0 do
        table.remove(self.updateCommands_, 1)()
    end

    local newFListContent = upd.readFile(upd.conf.UPDATE_LIST_FILE .. ".upd")
    if newFListContent then
        io.writefile(upd.conf.UPDATE_LIST_FILE, newFListContent, "wb+")
    end
    self.view_:setProgressTipsInfo(upd.lang.getText("UPDATE", "UPDATE_COMPLETE"))

    --test modify
    local needLoadFileList = clone(self.fileListNew_)
    if needLoadFileList and needLoadFileList.stage then
        table.filter(needLoadFileList.stage, function(v, k)
            return (1 ~= tonumber(v.silent))
        end)

        needLoadFileList.stage = table.values(needLoadFileList.stage)
    end

    -- dump(needLoadFileList,"needLoadFileList :======")
    self:endUpdate_(needLoadFileList)
end

function UpdateController:completedSilentUpdate()
    while #self.silentUpdateCommands_ > 0 do
        table.remove(self.silentUpdateCommands_, 1)
    end
end

function UpdateController:endUpdate()
    self:endUpdate_(self.fileList_)
end

function UpdateController:endUpdate_(fileList)
    self.view_:setUpdateInfoVisible(false)

    local version = fileList.ver
    if #(string.split(version, ".")) == 3 then
        version = version .. ".0"
    end

    BM_UPDATE = {}
    BM_UPDATE.VERSION = version
    BM_UPDATE.FACEBOOK_BONUS = self.FACEBOOK_BONUS
    BM_UPDATE.FEEDBACK_URL = self.feedBackUrl
    BM_UPDATE.LOGIN_URL = self.loginUrl
    BM_UPDATE.COMMENT_URL = self.commentUrl
    BM_UPDATE.STAGE_FILE_LIST = clone(fileList.stage)

    log("UpdateController:endUpdate_ ....")
    display.addSpriteFrames("common_texture.plist", "common_texture.png", function()
        log("common_texture Load Done!")
        display.addSpriteFrames("hall_texture.plist", "hall_texture.png", function()
            log("hall_texture Load Done!")
            self.view_:playLeaveScene(function()
                log("self.view_:playLeaveScene Callback Called!")

                require("appentry")
            end)
        end)
    end)
end

return UpdateController