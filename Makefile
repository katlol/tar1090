update:
	git fetch -a upstream
	git rebase upstream/master
	git push --force origin master
