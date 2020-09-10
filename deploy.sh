#!/bin/bash
PROFILE=$1                                                                                                                                       
PROJECT=SpringRestApiOld                                                                                                                             
PROJECT_HOME=/Users/jdj/Desktop/deploy/${PROJECT}                                                                                                      
JAR_PATH=${PROJECT_HOME}/build/libs/api-0.0.1-SNAPSHOT.jar                                                                                       
SVR_LIST=server_${PROFILE}.list                                                                                                                   
SERVERS=`cat $SVR_LIST`                                                                                                                           
DEPLOY_PATH=/home/ubuntu/apiexam

AWS_ID=ubuntu
DATE=`date +%Y-%m-%d-%H-%M-%S`        
JAVA_OPTS="-XX:MaxMetaspaceSize=128m -XX:+UseG1GC -Xss1024k -Xms128m -Xmx128m -Dfile.encoding=UTF-8"
PEM=AwsFreetierKeyPair.pem                                                                                                                       
PORT=8083                                                                                                             

echo Deploy Start                     
for server in $SERVERS; do                              
    echo Target server - $server
    # Target Server에 배포 디렉터리 생성           
    ssh -p 60079 $AWS_ID@$server "mkdir -p $DEPLOY_PATH/dist"                                                                                
    # Target Server에 jar 이동
    echo 'Executable Jar Copying...'
    echo $JAR_PATH
    scp -P 60079 $JAR_PATH $AWS_ID@$server:~/apiexam/dist/$PROJECT-$DATE.jar
    # 이동한 jar파일의 바로가기(SymbolicLink)생성                             
    ssh -p 60079 $AWS_ID@$server "ln -Tfs $DEPLOY_PATH/dist/$PROJECT-$DATE.jar $DEPLOY_PATH/$PROJECT"      
    echo 'Executable Jar Copyed'
    # 현재 실행중인 서버 PID 조회
    runPid=$(ssh -p 60079 $AWS_ID@$server pgrep -f $PROJECT)
    if [ -z $runPid ]; then            
        echo "No servers are running"                             
    fi                                                                                                                                       
    # 현재 실행중인 서버의 포트를 조회. 추가로 실행할 서버의 포트 선정                              
    runPortCount=$(ssh -p 60079 $AWS_ID@$server ps -ef | grep $PROJECT | grep -v grep | grep $PORT | wc -l)
    if [ $runPortCount -gt 0 ]; then        
        PORT=8084                             
    fi                                                                                                                                                                     
    echo "Server $PORT Starting..."
    # 새로운 서버 실행
    ssh -p 60079 $AWS_ID@$server "nohup java -jar -Dserver.port=$PORT -Dspring.profiles.active=$PROFILE $JAVA_OPTS $DEPLOY_PATH/$PROJECT < /dev/null > std.out 2> std.err &"
    # 새롭게 실행한 서버의 health check
    echo "Health check $PORT"                             
    for retry in {1..15}
    do    
        health=$(ssh -p 60079 $AWS_ID@$server curl -s http://localhost:$PORT/actuator/health)                      
        checkCount=$(echo $health | grep 'UP' | wc -l)
        echo "Check count - $checkCount"    
        if [ $checkCount -ge 1 ]; then      
           echo "Server $PORT Started Normaly"                  
           # 기존 서버 Stop
           if [ $runPid -gt 0 ]; then             
                echo "Server $runPid Stopping..."           
                ssh -p 60079 $AWS_ID@$server "kill -TERM $runPid"
                sleep 5
                echo "Server $runPid Stopped"           
                echo "Nginx Port Change"           
    ssh -p 60079 $AWS_ID@$server "echo 'set \$service_addr http://127.0.0.1:$PORT;' | sudo tee /etc/nginx/conf.d/service_addr.inc"
                echo "Nginx reload"           
    ssh -p 60079 $AWS_ID@$server "sudo service nginx reload"
           fi
           break;                         
     else
         echo "Check - false"
           fi                         
        sleep 5     
    done                   
    if [ $retry -eq 15 ]; then
     echo "Deploy Fail"
    fi                 
done                      
echo Deploy End

