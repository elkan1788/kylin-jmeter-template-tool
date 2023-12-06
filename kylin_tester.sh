#!/bin/bash
# 
# 执行Kylin查询请求自动化测试的脚本
#
# Author: 凡梦星尘 | elkan1788@139.com
# Date: 2023-11-25
# Version: 2.3.0

# JMeter执行文件根目录
ROOT=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
echo "JMeter压测工具的安装目录为：$ROOT"

# 检查是否存在JMeter执行文件
JMETER_BIN="./bin/jmeter.sh"
if [ ! -f $JMETER_BIN ]; then
  echo -e "\033[31m未找到JMeter的可执行文件\033[0m，请检查是否使用标准的Apache JMeter测试工具!!!" && exit 1
fi

# 执行测试的参数
USERS=1
RAMP_TIME=5
LOOP_COUNT=-1
DURATION_TIME=60
COMPLEX_RATION=10
DEBUG_ON="false"

# Kylin 参数配置
DEF_CONF_FILE="conf.ini"
CONF_FILE=$DEF_CONF_FILE
PROTOCOL="http"
KYLIN_HOST="127.0.0.1"
KYLIN_PORT="7070"
KYLIN_USER="ADMIN"
KYLIN_PSWD="KYLIN"
KYLIN_PROJ="learn_kylin"
B64_AUTH="QURNSU46S1lMSU4="
LIMIT_MIN=1
LIMIT_MAX=500

# 测试报告输出
DEF_JMETER_SCRIPT="scripts/kylin-http-stress-template.jmx"
JMETER_SCRIPT=$DEF_JMETER_SCRIPT
DEF_SQL_CSV_FILE="scripts/kylin-query-sqls.csv"
SQL_CSV_FILE=$DEF_SQL_CSV_FILE
REPORT_OUTPUT_NAME=""
REPORT_OUTPUT_ROOT="report/"
REPORT_OUTPUT_DIR=""
REPORT_OUTPUT_LOG=".log"
REPORT_OUTPUT_JTL=".jtl"

# 简易WEB服务
PY_ENV_VER=2
REPORT_SERVER_IP=$(python -c "import socket; print(socket.gethostbyname(socket.gethostname()))")
REPORT_SERVER_PORT=9999
REPORT_SERVER_PID="REPORT_SERVER_PID"

# 输出参数说明
function help() {
  echo "示例: kylin_tester.sh <命令>"
  echo "命令:"
  echo "  -i   KYLIN配置参数文件的相对路径"
  echo "  -q   KYLIN查询SQL文件的相对路径"
  echo "  -j   JMeter测试脚本的相对路径"
  echo "  -o   测试结果输出名称，包括日志名称，脚本记录，HTML报告"
  echo "  -u   并发测试用户数，默认为：1"
  echo "  -l   测试轮循次数，默认为-1，表示使用持续时间方式"
  echo "  -r   并发测试用户唤起时间，单位：秒，默认为5秒"
  echo "  -d   并发测试的持续时间，单位：秒，默认为60秒"
  echo "  -c   复杂SQL执行比例（0-100），默认为10"
  echo "  -b   是否开启Debug模式，默认为false"
  echo "  -e   用Base64加密认证信息，用:号隔开用户与密码"
  echo "  -w   启停简易WEB服务，可选操作：start|stop"
}

# 获取参数值
function getProps() {
  while IFS=":" read -r key value; do  
    case $key in  
      protocol)  
        PROTOCOL=$value  
        ;;
      kylin_host)  
        KYLIN_HOST=$value  
        ;;
      kylin_port)  
        KYLIN_PORT=$value  
        ;;
      kylin_user)  
        KYLIN_USER=$value  
        ;;
      kylin_pswd)  
        KYLIN_PSWD=$value  
        ;;
      kylin_proj)
        KYLIN_PROJ=$value
        ;;
      limit_min)
        LIMIT_MIN=$value
        ;;
      limit_max)
        LIMIT_MAX=$value
        ;;
      server_port)
        REPORT_SERVER_PORT=$value
        ;;
      *)
        echo -e "\033[31m未知参数配置：$key=$value \033[0m"
        ;;
    esac  
  done < "$CONF_FILE"
}

# 解析用户自定义测试参数
function parseArgs() {

  while getopts "i:q:j:o:u:l:r:d:c:b:w:e:h" opt; do
    case $opt in
    i)
      CONF_FILE=$OPTARG
      ;;
    q)
      SQL_CSV_FILE=$OPTARG
      ;;
    j)
      JMETER_SCRIPT=$OPTARG
      ;;
    o)
      REPORT_OUTPUT_NAME=$OPTARG
      ;;
    u)
      USERS=$OPTARG
      ;;
    l)
      LOOP_COUNT=$OPTARG
      ;;
    r)
      RAMP_TIME=$OPTARG
      ;;
    d)
      DURATION_TIME=$OPTARG
      ;;
    c)
      COMPLEX_RATION=$OPTARG
      ;;
    b)
      DEBUG_ON=$OPTARG
      ;;
    s)
      if [ "$OPTARG" == "start" ] && [ ! -f $REPORT_SERVER_PID ]; then
        webServer
      elif [ "$OPTARG" == "start" ] && [ -f $REPORT_SERVER_PID ]; then
        echo -e "测试报告的WEB服务\033[32m已在运行中\033[0m"
      elif [ "$OPTARG" == "stop" ] && [ -f $REPORT_SERVER_PID ]; then
        kill -9 "$(cat $REPORT_SERVER_PID)" 
        rm -rf ./$REPORT_SERVER_PID        
        echo -e "测试报告的WEB服务\033[32m已成功停止\033[0m"
      elif [ "$OPTARG" != "start" ] && [ "$OPTARG" != "stop" ]; then
        echo -e "发现使用了并不支持的参数：\033[31m$OPTARG\033[0m，请检查!!!"
      else
        echo "测试报告的WEB服务并未启动!!!"
      fi
      exit 0
      ;;
    e)
      encryptB64 $OPTARG
      exit 0
      ;;
    h)
      help
      exit 0
      ;;
    ?)
      echo -e "\033[31m 不支持的参数: $opt$OPTARG \033[0m" && exit 1
      ;;
    esac
  done
  shift $((OPTIND - 1))

}

# 检查JMeter测试必要的参数
function checkArgs() {

  if [ $CONF_FILE!=$DEF_CONF_FILE ] && [ ! -f $CONF_FILE ]; then
    echo "提示：请检查Kylin配置参数文件是否正确!!!"
    echo -e "      当前Kylin配置参数文件路径为：\033[31m$CONF_FILE\033[0m" && exit 1
  fi

  if [ $SQL_CSV_FILE!=$DEF_SQL_CSV_FILE ] && [ ! -f $SQL_CSV_FILE ]; then
    echo "提示：请检查SQL文件路径是否正确!!!"
    echo -e "      当前查询SQL文件路径为：\033[31m$SQL_CSV_FILE\033[0m" && exit 1
  fi

  if [ $JMETER_SCRIPT!=$DEF_JMETER_SCRIPT ] && [ ! -f $JMETER_SCRIPT ]; then
    echo "提示：请检查JMeter测试脚本配置是否正确!!!"
    echo -e "      当前JMeter脚本路径为：\033[31m$JMETER_SCRIPT\033[0m" && exit 1
  fi

  # 根据时间生成报告名称
  if [ -z $REPORT_OUTPUT_NAME ]; then
    current_ts=$(date +%Y%m%d%H%M%S)
    if [ $LOOP_COUNT -eq -1 ]; then
      REPORT_OUTPUT_NAME="users${USERS}_${DURATION_TIME}s_${current_ts}"
    else
      REPORT_OUTPUT_NAME="users${USERS}_${LOOP_COUNT}l_${current_ts}"
    fi
  fi

  REPORT_OUTPUT_DIR=$REPORT_OUTPUT_ROOT$REPORT_OUTPUT_NAME
  REPORT_OUTPUT_LOG=$REPORT_OUTPUT_DIR$REPORT_OUTPUT_LOG
  REPORT_OUTPUT_JTL=$REPORT_OUTPUT_DIR$REPORT_OUTPUT_JTL

  # 当有已存在报告时退出，JMeter报告暂不支持覆盖操作
  if [ -f $REPORT_OUTPUT_LOG ] || [ -f $REPORT_OUTPUT_JTL ] || [ -d $REPORT_OUTPUT_DIR ]; then
    echo "提示：请检查JMeter测试结果输出名称是否已存在!!!"
    echo "      路径为：$REPORT_OUTPUT_DIR" 
    echo "      日志为：$REPORT_OUTPUT_LOG" 
    echo "      记录为：$REPORT_OUTPUT_JTL"  && exit 1
  fi

  echo " Kylin配置为：$CONF_FILE"
  echo "   SQL文件为：$SQL_CSV_FILE"
  echo "测试的脚本为：$JMETER_SCRIPT"
  echo "测试报告输出：$REPORT_OUTPUT_DIR"
  echo "测试日志文件：$REPORT_OUTPUT_LOG"
  echo "测试记录文件：$REPORT_OUTPUT_JTL"

}

# 替换JMeter的设置
function replaceSets() {

  if [ $DEBUG_ON = "false" ]; then
    # 关闭对返回代码的断言
    sed -i '/testname="Result Code Assertion" enabled="true"/s/true/false/g' $JMETER_SCRIPT
    sed -i '/testname="Except Mesg Assertion" enabled="true"/s/true/false/g' $JMETER_SCRIPT
  else
    # 开启对返回代码的断言
    echo -e "\033[31m请注意正在使用Debug模式，建议在正式测试时关闭!!!\033[0m"
    sed -i '/testname="Result Code Assertion" enabled="false"/s/false/true/g' $JMETER_SCRIPT
    sed -i '/testname="Except Mesg Assertion" enabled="false"/s/false/true/g' $JMETER_SCRIPT
  fi

  # 根据不同测试方式设置参数
  if [ $LOOP_COUNT -eq -1 ]; then
    echo "持续时长为：${DURATION_TIME}s"
    sed -i '/<boolProp name="ThreadGroup.scheduler">false<\/boolProp>/s/false/true/g' $JMETER_SCRIPT
  else
    echo "循环次数为：$LOOP_COUNT"
    sed -i '/<boolProp name="ThreadGroup.scheduler">true<\/boolProp>/s/true/false/g' $JMETER_SCRIPT
  fi

}

# BASE64算法加密
function encryptB64 () {

  local IS_EMPTY=$( [ -z "$1" ] && echo "0" || echo "1" )

  if [[ $IS_EMPTY -eq 1 ]]; then
    B64_AUTH=$1
  else
    B64_AUTH=$KYLIN_USER":"$KYLIN_PSWD
  fi

  B64_AUTH=$(python -c "import base64; print(base64.b64encode('$B64_AUTH'))")

  if [[ $IS_EMPTY -eq 1 ]]; then
    echo "Base64加密的结果为：$B64_AUTH"
  fi

}

# 启动简易WEB服务
function webServer() {

  local CHECK_PORT_USED=$(netstat -ano | grep ":$REPORT_SERVER_PORT")
  if [ -n "$CHECK_PORT_USED" ]; then  
    echo -e "\033[31m请检查，端口号${REPORT_SERVER_PORT}已被占用!!!\033[0m"  
    exit 1      
  fi

  cd report
  nohup python -m SimpleHTTPServer $REPORT_SERVER_PORT > /dev/null 2>&1 &
  
  local PID=$!
  echo "$PID" > $REPORT_SERVER_PID
  echo -e "测试报告的WEB服务\033[32m已启动成功\033[0m，进程ID为：$PID"
  echo "请打开浏览器访问: http://$HOST_IP:$REPORT_SERVER_PORT/"
}

# 提交测试任务
function start() {
  
  echo "并发用户数为：$USERS"
  nohup $JMETER_BIN \
    -Jsqlfile=$ROOT"/"$SQL_CSV_FILE \
    -Jhost=$KYLIN_HOST \
    -Jport=$KYLIN_PORT \
    -Jb64auth=$B64_AUTH \
    -Jprojname=$KYLIN_PROJ \
    -Jlimitmin=$LIMIT_MIN \
    -Jlimitmax=$LIMIT_MAX \
    -Jusers=$USERS \
    -Jtime=$DURATION_TIME \
    -Jcration=$COMPLEX_RATION \
    -Jrtime=$RAMP_TIME \
    -Jloop=$LOOP_COUNT \
    -n -t $JMETER_SCRIPT \
    -l $REPORT_OUTPUT_JTL \
    -e -o $REPORT_OUTPUT_DIR > $REPORT_OUTPUT_LOG 2>/dev/null &
  
  local PID="$!"
  echo -e "此次测试任务\033[32m已提交\033[0m，进程ID为：$PID，详细测试过程如下："
  tail -f $REPORT_OUTPUT_LOG --pid $PID

  if ps -p $PID > /dev/null; then  
    echo "测试发生未知异常，任务还在进行，正在进行强制结束..."
    kill -9 $PID
  fi
  
  echo -e "\033[32m测试任务已完成\033[0m"
  echo "请打开查看测试报告：http://${REPORT_SERVER_IP}:${REPORT_SERVER_PORT}/${REPORT_OUTPUT_DIR}/index.html"

}

function main() {
  
  parseArgs "$@"

  if [ ! -d $REPORT_OUTPUT_ROOT ]; then
    mkdir $REPORT_OUTPUT_ROOT
  fi

  checkArgs
  getProps
  encryptB64
  replaceSets
  start

}

main "$@";