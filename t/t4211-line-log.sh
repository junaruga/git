#!/bin/sh

test_description='test log -L'
. ./test-lib.sh

test_expect_success 'setup (import history)' '
	git fast-import < "$TEST_DIRECTORY"/t4211/history.export &&
	git reset --hard
'

canned_test_1 () {
	test_expect_$1 "$2" "
		git log $2 >actual &&
		test_cmp \"\$TEST_DIRECTORY\"/t4211/expect.$3 actual
	"
}

canned_test () {
	canned_test_1 success "$@"
}
canned_test_failure () {
	canned_test_1 failure "$@"
}

test_bad_opts () {
	test_expect_success "invalid args: $1" "
		test_must_fail git log $1 2>errors &&
		test_i18ngrep '$2' errors
	"
}

canned_test "-L 4,12:a.c simple" simple-f
canned_test "-L 4,+9:a.c simple" simple-f
canned_test "-L '/long f/,/^}/:a.c' simple" simple-f
canned_test "-L :f:a.c simple" simple-f-to-main

canned_test "-L '/main/,/^}/:a.c' simple" simple-main
canned_test "-L :main:a.c simple" simple-main-to-end

canned_test "-L 1,+4:a.c simple" beginning-of-file

canned_test "-L 20:a.c simple" end-of-file

canned_test "-L '/long f/',/^}/:a.c -L /main/,/^}/:a.c simple" two-ranges
canned_test "-L 24,+1:a.c simple" vanishes-early

canned_test "-M -L '/long f/,/^}/:b.c' move-support" move-support-f
canned_test "-M -L ':f:b.c' parallel-change" parallel-change-f-to-main

canned_test "-L 4,12:a.c -L :main:a.c simple" multiple
canned_test "-L 4,18:a.c -L ^:main:a.c simple" multiple-overlapping
canned_test "-L :main:a.c -L 4,18:a.c simple" multiple-overlapping
canned_test "-L 4:a.c -L 8,12:a.c simple" multiple-superset
canned_test "-L 8,12:a.c -L 4:a.c simple" multiple-superset

test_bad_opts "-L" "switch.*requires a value"
test_bad_opts "-L b.c" "argument not .start,end:file"
test_bad_opts "-L 1:" "argument not .start,end:file"
test_bad_opts "-L 1:nonexistent" "There is no path"
test_bad_opts "-L 1:simple" "There is no path"
test_bad_opts "-L '/foo:b.c'" "argument not .start,end:file"
test_bad_opts "-L 1000:b.c" "has only.*lines"
test_bad_opts "-L :b.c" "argument not .start,end:file"
test_bad_opts "-L :foo:b.c" "no match"

test_expect_success '-L X (X == nlines)' '
	n=$(wc -l <b.c) &&
	git log -L $n:b.c
'

test_expect_success '-L X (X == nlines + 1)' '
	n=$(expr $(wc -l <b.c) + 1) &&
	test_must_fail git log -L $n:b.c
'

test_expect_success '-L X (X == nlines + 2)' '
	n=$(expr $(wc -l <b.c) + 2) &&
	test_must_fail git log -L $n:b.c
'

test_expect_success '-L ,Y (Y == nlines)' '
	n=$(printf "%d" $(wc -l <b.c)) &&
	git log -L ,$n:b.c
'

test_expect_success '-L ,Y (Y == nlines + 1)' '
	n=$(expr $(wc -l <b.c) + 1) &&
	git log -L ,$n:b.c
'

test_expect_success '-L ,Y (Y == nlines + 2)' '
	n=$(expr $(wc -l <b.c) + 2) &&
	git log -L ,$n:b.c
'

test_expect_success '-L with --first-parent and a merge' '
	git checkout parallel-change &&
	git log --first-parent -L 1,1:b.c
'

test_expect_success '-L with --output' '
	git checkout parallel-change &&
	git log --output=log -L :main:b.c >output &&
	test_must_be_empty output &&
	test_line_count = 70 log
'

test_expect_success 'range_set_union' '
	test_seq 500 > c.c &&
	git add c.c &&
	git commit -m "many lines" &&
	test_seq 1000 > c.c &&
	git add c.c &&
	git commit -m "modify many lines" &&
	git log $(for x in $(test_seq 200); do echo -L $((2*x)),+1:c.c; done)
'

test_expect_success '-s shows only line-log commits' '
	git log --format="commit %s" -L1,24:b.c >expect.raw &&
	grep ^commit expect.raw >expect &&
	git log --format="commit %s" -L1,24:b.c -s >actual &&
	test_cmp expect actual
'

test_expect_success '-p shows the default patch output' '
	git log -L1,24:b.c >expect &&
	git log -L1,24:b.c -p >actual &&
	test_cmp expect actual
'

test_expect_success '--raw is forbidden' '
	test_must_fail git log -L1,24:b.c --raw
'

# Create the following linear history, where each commit does what its
# subject line promises:
#
#   * 66c6410 Modify func2() in file.c
#   * 50834e5 Modify other-file
#   * fe5851c Modify func1() in file.c
#   * 8c7c7dd Add other-file
#   * d5f4417 Add func1() and func2() in file.c
test_expect_success 'setup for checking line-log and parent oids' '
	git checkout --orphan parent-oids &&
	git reset --hard &&

	cat >file.c <<-\EOF &&
	int func1()
	{
	    return F1;
	}

	int func2()
	{
	    return F2;
	}
	EOF
	git add file.c &&
	test_tick &&
	git commit -m "Add func1() and func2() in file.c" &&

	echo 1 >other-file &&
	git add other-file &&
	git commit -m "Add other-file" &&

	sed -e "s/F1/F1 + 1/" file.c >tmp &&
	mv tmp file.c &&
	git commit -a -m "Modify func1() in file.c" &&

	echo 2 >other-file &&
	git commit -a -m "Modify other-file" &&

	sed -e "s/F2/F2 + 2/" file.c >tmp &&
	mv tmp file.c &&
	git commit -a -m "Modify func2() in file.c" &&

	head_oid=$(git rev-parse --short HEAD) &&
	prev_oid=$(git rev-parse --short HEAD^) &&
	root_oid=$(git rev-parse --short HEAD~4)
'

# Parent oid should be from immediate parent.
test_expect_success 'parent oids without parent rewriting' '
	cat >expect <<-EOF &&
	$head_oid $prev_oid Modify func2() in file.c
	$root_oid  Add func1() and func2() in file.c
	EOF
	git log --format="%h %p %s" --no-patch -L:func2:file.c >actual &&
	test_cmp expect actual
'

# Parent oid should be from the most recent ancestor touching func2(),
# i.e. in this case from the root commit.
test_expect_success 'parent oids with parent rewriting' '
	cat >expect <<-EOF &&
	$head_oid $root_oid Modify func2() in file.c
	$root_oid  Add func1() and func2() in file.c
	EOF
	git log --format="%h %p %s" --no-patch -L:func2:file.c --parents >actual &&
	test_cmp expect actual
'

test_done
