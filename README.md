# Cài đặt Openshift 4 trong môi trường không có kết nối internet
Red Hat kể từ phiên bản __openshift-install__ CLI 4.12 đã có tính năng agent-based install, cho phép chúng ta triển khai openshift dễ dàng hơntrong những môi trường đòi hỏi độ tùy biến cao. Nó mang lại trải nghiệm phần nào tự động trong các bước cài đặt mà ở đó chúng ta chỉ cần chuẩn bị các thông tin hạ tầng như địa chỉ IP của các node, DNS records,...
Hướng dẫn này sẽ giúp các bạn rõ hơn về những bước cần thực hiện để cài đặt Openshift bằng cách sử dụng tính năng agent-based của trình cài đặt __openshift-install__. Chúng ta cũng sẽ thử cài đặt openshift ở môi trường không có kết nối internet (disconnected).
Để cài Openshift cluster trong môi trường không có kết nối internet, chúng ta cần phải thực hiện các bước sau:

1. Triển khai _mirror Quay registry_ - chúng ta sẽ mirror toàn bộ nội dung  cần thiết cho việc cài đặt từ cloud của Red Hat về registry nội bộ này
2. Nếu bạn dùng trình cài đặt _openshift-install bản 4.11_ thì chúng ta cần phải build lại trình cài đặt này để thêm tính năng _agent-based install_
3. Tiếp theo chúng ta cần tạo file ISO để cài hệ điều hành RHCoreOS lên các node
4. Và cuối cùng là theo dõi tiến trình cài đặt và thực hiện một số thiết lập ban đầu (phần thiết lập ban đầu các bạn có thể tham khảo them clip trên youtube)

Các bạn có thể tham khảo clip thực hiện trên kênh youtube [RedHat VN Labs](https://www.youtube.com/@rhvnlabs)

Để chuẩn bị, chúng ta cần:
- 1 máy bastion host chạy RHEL8 với giao diện GUI có Firefox (4vCPU, 8Gb RAM, HDD 120Gb) - chúng ta sẽ tương tác với openshift thông qua bastion host này. Host này cũng sẽ làm mirror registry luôn (trong clip chúng tôi dùng tên __quay__ cho host này, tuy nhiên bên dưới trong phần hướng dẫn chúng tôi vẫn để là __bastion__ để các bạn dễ follow)
- 3 master node (8vCPU, 16Gb RAM, HDD 120Gb) - HĐH sẽ đựoc cài đặt sau
- 2 worker node (8vCPU, 16Gb RAM, HDD 120Gb) - HĐH sẽ đựoc cài đặt sau

Ngoài ra chúng ta cũng cần có 1 DNS server với tên miền tùy chọn (trong lab này chúng ta sử dụng _Red Hat IdM server_, với internal domain là _vnlabs.dev_). Trong nội dung hướng dẫn, chỗ nào dùng tên miền _vnlabs.dev_ thì các bạn thay bằng tên miền tùy chọn của các bạn

Chúng ta cũng giả định tên đăng nhập vào bastion host là __user__ (trong youtube clip các bạn thấy là _thanhnq_) 

Với đầy đủ sự chuẩn bị ở trên, các buớc thực hiện chi tiết như sau:

## Triển khai mirror Quay registry
Trước khi thực hiện chúng ta cần truy cập vào [https://console.redhat.com](https://console.redhat.com) để tải về:
- pull secret
- __oc__ command-line tool 
- __openshift-install__ command-line tool 

Copy các file download về bastion host, thư mục _/home/user_
```
[user@bastion ~]# tar zxf openshift-client-linux.tar.gz
[user@bastion ~]# tar zxf openshift-install-linux.tar.gz
[user@bastion ~]# mkdir /home/user/bin
[user@bastion ~]# mv oc kubectl openshift-install ~/bin
```
tạo thư mục _~/mirror_, cho pull secret vào thư mục _mirror_ và đặt tên file cho nó là _pull-secret.txt_
```
[user@bastion ~]# mkdir ~/mirror && mv pull-secret.txt mirror/
```

Cài đặt các gói phần mềm cần thiết trên bastion host
```
[user@bastion ~]# cd mirror
[user@bastion mirror]# sudo yum install -y podman httpd-tools openssl tmux \
                        net-tools nmstate git golang make zip bind-utils jq
```

Thiết lập thư mục chứa nội dung cho mirror registry và tiến hành cài đặt registry
```
[user@bastion mirror]# echo 'export REGISTRY_SERVER=bastion.vnlabs.dev' >> ~/.bashrc
[user@bastion mirror]# source ~/.bashrc
[user@bastion mirror]# sudo mkdir /quay
[user@bastion mirror]# curl -sL https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry.tar.gz -o - | tar xzvf -
[user@bastion mirror]# sudo ./mirror-registry install --quayHostname $REGISTRY_SERVER --quayRoot /quay
```

Sau khi hoàn tất cài đặt, màn hình sẽ hiển thị username (__init__) và password của registry, lưu lại các thông tin đó bằng cách thực hiện  2 câu lệnh sau để dễ dàng tham chiếu về sau:
```
[user@bastion mirror]# echo 'REGISTRY_PW=xxxxxxxyyyyyyyyyyzzzzzzzzzzz' >> ~/.bashrc
[user@bastion mirror]# source ~/.bashrc
```
(lưu ý việc lưu thông tin password vào file môi trường sẽ gây ra rủi ro bảo mật lớn, nên chúng ta chỉ thực hiện điều này trong lab mà thôi)

Tiếp theo, update trusted CA trên bastion host
```
[user@bastion mirror]# sudo cp /quay/quay-rootCA/rootCA* /etc/pki/ca-trust/source/anchors/ -v
[user@bastion mirror]# sudo update-ca-trust extract
```

Login vào registry
```
[user@bastion mirror]# podman login --authfile pull-secret.txt -u init \
                        -p $REGISTRY_PW $REGISTRY_SERVER:8443 --tls-verify=false
```
sau câu lệnh đăng nhập này, một mục nội dung secret tương ứng với tên của mirror registry sẽ đựoc tự động thêm vào pull-secret.txt, chúng ta có thể kiểm tra bằng cách xem nội dung file này.

Tiếp theo, sử dụng _jq_ để chuyển pull-secret.txt sang dạng _json_ và copy vào các đường dẫn cần thiết
```
[user@bastion mirror]# cat ./pull-secret.txt | jq . > pull-secret.json
[user@bastion mirror]# mkdir -p ~/.config/containers
[user@bastion mirror]# cp pull-secret.json ~/.config/containers/auth.json
[user@bastion mirror]# mkdir ~/.docker
[user@bastion mirror]# cp pull-secret.json ~/.docker/config.json
```

Tiếp theo, chúng ta cấu hình firewall trên bastion host 
```
[user@bastion mirror]# sudo firewall-cmd --add-port 8443/tcp --permanent
[user@bastion mirror]# sudo firewall-cmd --add-service dns --permanent
[user@bastion mirror]# sudo firewall-cmd --reload
```

Đến dây chúng ta đã có thể sử dụng Firefox để truy cập vào registry: 
```
[user@bastion mirror]# echo $REGISTRY_SERVER 
```
sử dụng giá trị trả về để mở kết nối trên Firefox, ví dụ: https://bastion.vnlabs.dev:8443 

Tiếp theo, chúng ta cài đặt oc-mirror tool 
```
[user@bastion mirror]# curl -L -s -o - https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz |sudo tar x -C /usr/local/bin -vzf - oc-mirror && sudo chmod +x /usr/local/bin/oc-mirror
```

Chạy lệnh bên dưới để chắc chắn là thao tác cài đặt đã thành công
```
[user@bastion mirror]# oc mirror help
```

Thiết lập cấu hình để bắt đầu quá trình mirror
```
[user@bastion mirror]# oc mirror init --registry $REGISTRY_SERVER:8443/ocp4/openshift4/mirror/oc-mirror-metadata > imageset-config.yaml
```
sau khi câu lệnh thực hiện xong, chúng ta mở file _imageset-config.yaml_ để tùy chỉnh. Ví dụ:
- để mirror 1 phiên bản cụ thể (opensshift 4.11.6), chúng ta sửa nội dung sau:
```
platform:
channels:
- name: stable-4.11
minVersion: 4.11.6
maxVersion: 4.11.6
```

- để thêm 1 vài operator cần thiết, chúng ta sửa như sau:
```
operators:
- catalog: registry.redhat.io/redhat/redhat-operator-index:v4.11
packages:
- name: cincinnati-operator
- name: local-storage-operator
  channels:
  - name: stable
- name: odf-operator
- name: kubevirt-hyperconverged
  channels:
  - name: stable
```
(thao khảo file _imageset-config.yaml_ hoàn chỉnh trong github repo này)

Để xem danh sách các operator và channel có thể sử dụng với phiên bản openshift 4.11, chúng ta chạy lệnh:
```
[user@bastion mirror]# oc-mirror list operators --catalog registry.redhat.io/redhat/redhat-operator-index:v4.11
```
sau đó thêm vào file _imageset-config.yaml_ những operator cần thiết 

Cuối cùng, chúng ta chạy lệnh sau để thực hiện mirror
```
[user@bastion mirror]# oc mirror --config=./imageset-config.yaml docker://$REGISTRY_SERVER:8443
```

Lưu ý:
- quá trình này sẽ tạo 1 thư mục tên là __oc-mirror-workspace__ về sau chúng ta sẽ dùng nội dung trong thư mục này để hiển thi danh sách các operator được add vào trong file imageset-config.yaml 
- quá trình mirror sẽ kéo dài khoảng 30-60 phút tùy theo số lượng operator và chất lượng đường truyền internet

Thiết lập biến môi trường:
```
[user@bastion mirror]# export OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE=`hostname`:8443/openshift/release-images@<sha256 value>
```
_sha256 value_: 
- để có giá trị này, bạn vào trình duyệt và truy cập vào mirror registry (ví dụ https://bastion.vnlabs.dev:8443/openshift/release-images)
- vào Tags, trong cột MANIFEST, nhấn vào SHA256, sau đó copy giá trị SHA256 và paste vào câu lệnh trên
(xem thêm youtube clips nếu chưa rõ)

## Build openshift-install tool (tùy chọn)
Nếu bạn download openshift-install phiên bản 4.12 thì không cần thực hiện bước này
Với bản 4.11, do chưa hỗ trợ tính năng agent-based installation, nên chúng ta phải tự build.

Bạn có thể kiểm tra openshift-install của bạn bằng cách chạy _openshift-install_, nếu bên dưới Available Commands không có __agent__ (agent Commands for supporting cluster installation using agent installer) thì bạn sẽ cần thực hiện thao tác build này
```
[user@bastion mirror]# ~/bin/openshift-install
Creates OpenShift clusters


Usage:
openshift-install [command]


Available Commands:
analyze Analyze debugging data for a given installation failure
completion Outputs shell completions for the openshift-install command
coreos Commands for operating on CoreOS boot images
create Create part of an OpenShift cluster
destroy Destroy part of an OpenShift cluster
explain List the fields for supported InstallConfig versions
gather Gather debugging data for a given installation failure
graph Outputs the internal dependency graph for installer
help Help about any command
migrate Do a migration
version Print version information
wait-for Wait for install-time events


Flags:
--dir string assets directory (default ".")
-h, --help help for openshift-install
--log-level string log level (e.g. "debug | info | warn | error") (default "info")


Use "openshift-install [command] --help" for more information about a command.

```

Để build, bạn copy file billie-release.sh về máy bastion host, chmod cho nó:
```
[user@bastion mirror]# chmod +x billie-release.sh
```

Tiếp theo chúng ta chạy lệnh sau để build tool, câu lệnh bên dưới build __openshift-install__ tool cho __version 4.11.6__
```
[user@bastion mirror]# ./billi-release.sh agent-installer ${OPENSHIFT_INSTALL_RELEASE_IMAGE_OVERRIDE} 4.11.6
```

Quá trình build sẽ mất khoảng 45-60', sau khi build xong, chúng ta thử chạy lại lệnh openshift-install để xem tính năng agent đã lên chưa:
```
[user@bastion mirror]# ./openshift-install
Creates OpenShift clusters


Usage:
openshift-install [command]


Available Commands:
agent Commands for supporting cluster installation using agent installer
analyze Analyze debugging data for a given installation failure
completion Outputs shell completions for the openshift-install command
coreos Commands for operating on CoreOS boot images
create Create part of an OpenShift cluster
destroy Destroy part of an OpenShift cluster
explain List the fields for supported InstallConfig versions
gather Gather debugging data for a given installation failure
graph Outputs the internal dependency graph for installer
help Help about any command
migrate Do a migration
version Print version information
wait-for Wait for install-time events


Flags:
--dir string assets directory (default ".")
-h, --help help for openshift-install
--log-level string log level (e.g. "debug | info | warn | error") (default "info")


Use "openshift-install [command] --help" for more information about a command.
```

##  Tạo file ISO và Cài Openshift 

Tạo 1 thư mục mới trong mirror
```
[user@bastion mirror]# mkdir cluster
```

Sinh ra 1 ssh key để các node có thể được dễ dàng quản trị về sau
```
[user@bastion mirror]# ssh-keygen -t rsa -N '' -f node_ssh_key
```

Tạo 2 file _install-config.yaml_ và _agent-config.yaml_ trong thư mục cluster (thao khảo 2 file tương ứng trong repo này). 2 file này chứa các thông tin cần thiết để cài đặt cluster như địa chỉ IP, MAC, Gateway, DNS server,...

Đối với file _install-config.yaml_:
- _machineNetwork_: dải IP dành cho các node
- _sshKey_: là nội dung của file __node_ssh_key.pub__ 
- _pullSecret_: lấy phần tương ứng trong file pull-secret.json, dán vào theo json format, ví dụ:
```
pullSecret: '{"bastion.vnlabs.dev:8443": { "auth": "aW5pdDpYOGFxclJwWjJXSDFUOVFpR0NORHZBbjVvMzYwWTc0Uw==" } }'
```    
- _additionalTrustBundle_: là nội dung của file __/etc/pki/ca-trust/source/anchors/rootCA.pem__ trên bastion host

Tiếp theo, chúng ta sẽ tạo _Machineconfig_ sử dụng _butane_ để cấu hình chrony cho các node trong quá trình cài (https://docs.openshift.com/container-platform/4.11/installing/install_config/installing-customizing.html)
Truy cập vào địa chỉ https://mirror.openshift.com/pub/openshift-v4/clients/butane/ để kiểm tra và lấy link down load của version mới nhất 
Download _butane_ binary:       
```[user@bastion mirror]# curl https://mirror.openshift.com/pub/openshift-v4/clients/butane/latest/butane --output butane```

chmod để file có thể đựoc thực thi và move nó vào thư mục ~/bin
```
[user@bastion mirror]# chmod +x butane
[user@bastion mirror]# mv butane ~/bin/butane
```

Tạo file _99-worker-custom.bu_ - lưu ý đổi địa chỉ IP bên dưới trỏ đến NTP server mà bạn muốn sử dụng
```
[user@bastion mirror]# vi cluster/99-worker-custom.bu
variant: openshift
version: 4.11.0
metadata:
  name: 99-worker-custom
  labels:
    machineconfiguration.openshift.io/role: worker
openshift:
  kernel_arguments:
    - loglevel=7
  storage:
    files:
      - path: /etc/chrony.conf
        mode: 0644
        overwrite: true
        contents:
          inline: |
            pool 192.168.67.28 prefer iburst
            pool 192.168.67.254 iburst
            driftfile /var/lib/chrony/drift
            makestep 1.0 3
            rtcsync
            logdir /var/log/chrony
```

Tạo _Machineconfig_:
```
[user@bastion mirror]# butane cluster/99-worker-custom.bu -o cluster/99-worker-custom.yaml
```

Tiếp theo, chúng ta đã sẵn sàng để tạo file ISO, trước khi thực hiện:
- Backup các file trong thư mục cluster ra 1 vị trí khác 
- chúng ta cần __đảm bảo bastion host không ra được internet__. 
Sau khi ngắt kết nối internet của bastion, chúng ta thực hiện lệnh sau:
```
[user@bastion mirror]# ~/backup && cp cluster/*.yaml ~/backup
[user@bastion mirror]# ~/mirror/openshift-install agent create image --log-level debug --dir cluster
```

Sau khi câu lệnh chạy xong trong thư mục _cluster_ sẽ có 1 file __agent.iso__ và 1 thư mục _auth_ được tạo ra, đồng thời 2 file install-config.yaml và agent-config.yaml tự động bị xoá đi

Tiếp theo, chúng ta sẽ thực hiện các thao tác:
- Upload file agent.iso lên vmware, 
- mount nó vào các node đã được tạo sẵn dưới dạng CD-ROM, 
- và Power On các VM lên. 
Việc cài đặt openshift sẽ đựoc tự động thực hiện trong quá trình các node boot. 

Để theo dõi quá trình cài đặt, chúng ta thực hiện lệnh sau:
```
[user@bastion mirror]# ./openshift-install agent wait-for install-complete --dir cluster
```
quá trình này sẽ kéo dài khoảng 60', trong quá trình đó, các node sẽ đựoc tự động reboot vài lần, và có thể bạn sẽ thấy nột số thông báo FAILED, mặc kệ cho đến cuối cùng... 
Bạn sẽ được thông báo việc triển khai thành công hay thất bại. Nếu thất bại, bạn cần:
- xóa hết nội dung trong thư mục cluster, 
- copy các file đã backuop vào lại thư mục này, 
- xem lại nội dung các file yaml này xem đã đúng chưa (IP, MAC, Gateway, DNS, sshKey, secret,...)
- ... và thực hiện lại câu lệnh _openshift-install_ ở trên để tạo lại file iso, mount CD-ROM và reboot các máy (nhớ ở lần reboot này các node phải boot từ CD-ROM first).  
  

## Một số thiết lập ban đầu
Để có thể sử dụng cluster, chúng ta cần thiết lập 1 số cấu hình sau:

Thiết lập _kubeadmin_ password
```
[user@bastion mirror]# oc patch secret -n kube-system kubeadmin --type json \
  -p '[{"op": "replace", "path": "/data/kubeadmin", "value": "'"$(openssl rand -base64 18 | tee /home/thanhnq/mirror/cluster/auth/kubeadmin-password | htpasswd -nBi -C 10 "" | cut -d: -f2 | base64 -w 0 -)"'"}]'

secret/kubeadmin patched


[user@bastion mirror]# ls -l /home/thanhnq/mirror/cluster/auth/kubeadmin-password
-rw-r-----. 1 bschmaus bschmaus 25 Aug 18 10:50 auth/kubeadmin-password


[user@bastion mirror]# cat auth/kubeadmin-password
<YOUR KUBEADMIN PASSWORD>
```

Tiếp theo, bạn cần fix lỗi liên quan đến certificate, chạy câu lệnh dưới để kiểm tra xem bạn có bị lỗi hay không:
```
[user@bastion ~]# oc login
error: x509: certificate signed by unknown authority
[user@bastion ~]# oc whoami
system:admin
```

Cách xử lý trên bastion như sau: https://docs.openshift.com/container-platform/4.11/security/certificate_types_descriptions/ingress-certificates.html
```
[user@bastion ~]# oc get secret router-ca -n openshift-ingress-operator -o json | \
jq -r '.data."tls.crt"' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/ingress-root-CA.pem
[user@bastion ~]# oc get secret router-ca -n openshift-ingress-operator -o json | \
jq -r '.data."tls.crt"' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/ingress-root-CA.key


[user@bastion ~]# update-ca-trust extract
```

Tiếp theo, chúng ta disable default OperatorHub
```
[user@bastion ~]# oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
```

Sau đó, chúng ta sẽ install ImageContentSourcePolicy và CatalogSource resources vào cluster:
```
[user@bastion ~]# oc apply -f ./oc-mirror-workspace/results-1639608409/
[user@bastion ~]# oc get imagecontentsourcepolicy --all-namespaces
[user@bastion ~]# oc get catalogsource --all-namespaces
```

Cuối cùng, thêm identityProvider vào cluster, ví dụ, chúng ta sẽ thêm các user và password như sau để có thể xác thực vào cluster:
```
[user@bastion ~]# htpasswd -c -B -b ./ocp-user-passwd user1 p@ssw0rd1
[user@bastion ~]# htpasswd -b ./ocp-user-passwd user2 p@ssw0rd2
[user@bastion ~]# oc create secret generic local-idp-secret \
                  --from-file htpasswd=./ocp-user-passwd -n openshift-config
[user@bastion ~]# oc edit oauth cluster
spec:
identityProviders:
- htpasswd:
    fileData:
      name: local-idp-secret
      mappingMethod: claim
    name: local-users
    type: HTPasswd 
```

Phân quyền cho user, ví dụ user1 có quyền cluster-admin
```
[user@bastion ~]# oc adm policy add-cluster-role-to-user cluster-admin user1
```

Sau khi phân quyền xong, chúng ta có thể xóa user kubeadmin để giảm thiểu rủi ro bảo mật (lưu ý, chỉ thực hiện sau khi chúng ta đã có 1 user khác có quyền cluster-admin)
```
[user@bastion ~]# oc delete secret kubeadmin -n kube-system 
```

Như vậy là chúng ta đã cài đặt xong openshift cluster trong môi trường disconnected.

Các bạn có thể xem thêm youtube clip nếu chưa rõ các bước. 

Chúc các bạn thành công !

Nếu các bạn quan tâm đến Red Hat ở Việt Nam, xin vui lòng join Facebook group: https://facebook.com/groups/redhatvietnam