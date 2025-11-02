#!/bin/sh

HATHCID=$HathClientId
HATHKEY=$HathClientKey
EHIPBID=$StunIpbId
EHIPBPW=$StunIpbPass

WANADDR=$1
WANPORT=$2

echo 当前穿透通道为 $WANADDR:$WANPORT，即将更新 H@H 客户端设置信息

[ $StunProxy ] || echo 未配置 STUN 代理，请留意 H@H 客户端设置信息能否获取与更新
[ $StunProxy ] && PROXY='-x '$StunProxy''

# 保存穿透信息
touch /hath/stun.log
[ $(wc -l </hath/stun.log) -ge 1000 ] && mv /hath/stun.log /hath/stun.log.old
echo [$(date)] $WANADDR:$WANPORT '->' $HathPort >>/hath/stun.log
echo $WANPORT >/hath/WANPORT

# 定义与 RPC 服务器交互的函数
ACTION() {
	ACT=$1
	ACTTIME=$(date +%s)
	ACTKEY=$(echo -n "hentai@home-$ACT--$HATHCID-$ACTTIME-$HATHKEY" | sha1sum | cut -c -40)
	curl -Ls 'http://rpc.hentaiathome.net/15/rpc?clientbuild='$BUILD'&act='$ACT'&add=&cid='$HATHCID'&acttime='$ACTTIME'&actkey='$ACTKEY''
}

# 检测是否需要更改端口
if ACTION client_settings | grep -q "port=$WANPORT"; then
	echo 外部端口 $WANPORT/tcp 未发生变化
	SKIP=1
fi

# 获取 H@H 客户端设置信息（仅当需要更新时）
if [ -z "$SKIP" ]; then
	HATHPHP=/tmp/settings.php
	>$HATHPHP
	curl $PROXY -Ls -m 15 \
	-b "ipb_member_id=$EHIPBID; ipb_pass_hash=$EHIPBPW" \
	-o $HATHPHP \
	"https://e-hentai.org/hentaiathome.php?cid=$HATHCID&act=settings"

	f_cname=$(grep f_cname $HATHPHP | awk -F '"' '{print$6}' | sed 's/[ ]/+/g')
	f_throttle_KB=$(grep f_throttle_KB $HATHPHP | awk -F '"' '{print$6}')
	f_disklimit_GB=$(grep f_disklimit_GB $HATHPHP | awk -F '"' '{print$6}')
	p_mthbwcap=$(grep p_mthbwcap $HATHPHP | awk -F '"' '{print$6}')
	f_diskremaining_MB=$(grep f_diskremaining_MB $HATHPHP | awk -F '"' '{print$6}')
	f_enable_bwm=$(grep f_enable_bwm $HATHPHP | grep checked)
	f_disable_logging=$(grep f_disable_logging $HATHPHP | grep checked)
	f_use_less_memory=$(grep f_use_less_memory $HATHPHP | grep checked)
	f_is_hathdler=$(grep f_is_hathdler $HATHPHP | grep checked)

	# 发送暂停指令
	ACTION client_suspend >/dev/null

	# 构造并提交设置数据（仅一次）
	DATA="settings=1&f_port=$WANPORT&f_cname=$f_cname&f_throttle_KB=$f_throttle_KB&f_disklimit_GB=$f_disklimit_GB"
	[ "$p_mthbwcap" = 0 ] || DATA="$DATA&p_mthbwcap=$p_mthbwcap"
	[ "$f_diskremaining_MB" = 0 ] || DATA="$DATA&f_diskremaining_MB=$f_diskremaining_MB"
	[ "$f_enable_bwm" ] && DATA="$DATA&f_enable_bwm=on"
	[ "$f_disable_logging" ] && DATA="$DATA&f_disable_logging=on"
	[ "$f_use_less_memory" ] && DATA="$DATA&f_use_less_memory=on"
	[ "$f_is_hathdler" ] && DATA="$DATA&f_is_hathdler=on"

	curl $PROXY -Ls -m 15 \
	-b "ipb_member_id=$EHIPBID; ipb_pass_hash=$EHIPBPW" \
	-o $HATHPHP \
	-d "$DATA" \
	"https://e-hentai.org/hentaiathome.php?cid=$HATHCID&act=settings"

	# 验证更新结果（仅提示，不影响流程）
	if ACTION client_settings | grep -q "port=$WANPORT"; then
		echo 外部端口 $WANPORT/tcp 更新成功
	else
		echo 警告：端口更新可能未生效，请手动检查
	fi

	# 启动客户端
	ACTION client_start >/dev/null
fi

# 发送 client_start 后，检测是否需要启动 H@H 客户端
# 若客户端已启动，则自动恢复连接，无需重启
# 若客户端未启动，client_suspend 与 client_start 不会造成实质影响
ps aux | grep HentaiAtHome | grep -v grep >/dev/null || exec hath.sh &



