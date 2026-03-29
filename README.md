\# install Vagrant on Windows

winget install Hashicorp.Vagrant



\# install VirtualBox if not already

\# then just:

vagrant up



\# that's it — full cluster + Istio ambient in one command

\# get a shell into master

vagrant ssh master



\# verify

kubectl get nodes

kubectl get pods -n istio-system

