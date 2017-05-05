-- errormsg.lua
ErrorCode = {}

ErrorCode.ACCOUNT_REPEAT = 1			-- 账号重复
ErrorCode.DBSERVICE_ERROR = 99 			-- 数据错误
ErrorCode.NO_ACCOUNT = 101 				-- 账号不存在
ErrorCode.PASSWORD_ERROR = 102 			-- 密码错误
ErrorCode.HAS_ONLINE = 103 				-- 已经在线，请稍后重试
ErrorCode.NO_USER_ID = 105 				-- 用户ID不存在
ErrorCode.NOT_ONLINE = 106 				-- 用户不在线，无法操作
ErrorCode.ACCOUNT_SEAL = 107 			-- 账号被禁用，解禁日期为
ErrorCode.PHONE_CHECK_ERROR = 108 		-- 手机验证码检测失败


ErrorCode.ROOM_NOT_FOUND = 201 			-- 未找到该房间
ErrorCode.ROOM_FULL = 202 				-- 房间已满
ErrorCode.GOLD_NOT_ENOUGH = 301 		-- 金币不足
ErrorCode.BANKER_NO_BET = 401 			-- 庄家不能下注
ErrorCode.NOT_BANKER = 402 				-- 你不是庄家
ErrorCode.NOT_IN_QUEUE = 403 			-- 不在队列中
ErrorCode.UR_BANKER = 404 				-- 你已经是庄家
ErrorCode.HAS_IN_QUEUE = 405 			-- 你已经在队列
ErrorCode.TUIBING_ROOMCLOSE = 406 		-- 房间已关闭

 										
-- mahjong
ErrorCode.MAHJONG_ROOM_FULL = 501
ErrorCode.MAHJONG_PLAYER_NOT_FOUND = 502
ErrorCode.MAHJONG_MJ_NOT_FOUND = 503
ErrorCode.MAHJONG_ERROR_COMMAND = 504

-- DB
ErrorCode.DB_PLAYER_NOT_FOUND = 701		-- 数据库错误，找不到玩家

-- HTTP
ErrorCode.PARAM_ERROR = 801 			-- 运行参数错误
ErrorCode.SIGN_ERROR = 802				-- 验证失败
-- GM
ErrorCode.PERMISSION_DENIED = 901		-- 权限不足
ErrorCode.LOGTYPE_ERROR = 902			-- 日志类型错误
