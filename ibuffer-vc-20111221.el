;;; ibuffer-vc.el --- Group ibuffer's list by VC project, or show VC status
;;
;; Copyright (C) 2011 Steve Purcell
;;
;; Author: Steve Purcell <steve@sanityinc.com>
;; Keywords: themes
;; X-URL: http://github.com/purcell/ibuffer-vc
;; URL: http://github.com/purcell/ibuffer-vc
;; Version: DEV
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.
;;
;;; Commentary:
;;
;; Adds functionality to ibuffer for grouping buffers by their parent
;; vc root directory, and for displaying and/or sorting by the vc
;; status of listed files.
;;
;;; Use:
;;
;; To group buffers by vc parent dir:
;;
;;   M-x ibuffer-vc-set-filter-groups-by-vc-root
;;
;; or, make this the default:
;;
;;   (add-hook 'ibuffer-hook
;;     (lambda ()
;;       (ibuffer-vc-set-filter-groups-by-vc-root)
;;       (ibuffer-do-sort-by-alphabetic)))
;;
;; Alternatively, use `ibuffer-vc-generate-filter-groups-by-vc-root'
;; to programmatically obtain a list of filter groups that you can
;; combine with your own custom groups.
;;
;; To include vc status info in the ibuffer list, add either
;; vc-status-mini or vc-status to `ibuffer-formats':
;;
;; (setq ibuffer-formats
;;       '((mark modified read-only vc-status-mini " "
;;               (name 18 18 :left :elide)
;;               " "
;;               (size 9 -1 :right)
;;               " "
;;               (mode 16 16 :left :elide)
;;               " "
;;               (vc-status 16 16 :left)
;;               " "
;;               filename-and-process)))
;;
;; To sort by vc status, use `ibuffer-do-sort-by-vc-status', which can
;; also be selected by repeatedly executing
;; `ibuffer-toggle-sorting-mode' (bound to "," by default).
;;
;;; Code:

;; requires

(require 'ibuffer)
(require 'ibuf-ext)
(require 'vc-hooks)
(eval-when-compile
  (require 'cl))

(defgroup ibuffer-vc nil
  "Group ibuffer entries according to their version control status."
  :prefix "ibuffer-vc-"
  :group 'convenience)

(defcustom ibuffer-vc-skip-if-remote t
  "If non-nil, don't query the VC status of remote files."
  :type 'boolean
  :group 'ibuffer-vc)

;;; Group and filter ibuffer entries by parent vc directory

(defun ibuffer-vc--include-file-p (file)
  (and file (or (null ibuffer-vc-skip-if-remote)
                (not (file-remote-p file)))))

(defun ibuffer-vc--deduce-backend (file)
  (or (vc-backend file)
      (loop for backend in vc-handled-backends
            when (vc-call-backend backend 'responsible-p file)
            return backend)))

(defun ibuffer-vc-root (buf)
  "Return a cons cell (backend-name . root-dir), or nil if the
file is not under version control"
  (let ((file-name (with-current-buffer buf (or buffer-file-name default-directory))))
    (when (ibuffer-vc--include-file-p file-name)
      (let ((backend (ibuffer-vc--deduce-backend file-name)))
        (when backend
          (let* ((root-fn-name (intern (format "vc-%s-root" (downcase (symbol-name backend)))))
                 (root-dir
                  (cond
                   ((fboundp root-fn-name) (funcall root-fn-name file-name)) ; git, svn, hg, bzr (at least)
                   ((memq backend '(darcs DARCS)) (vc-darcs-find-root file-name))
                   ((memq backend '(cvs CVS)) (vc-find-root file-name "CVS"))
                   (t (error "ibuffer-vc: don't know how to find root for vc backend '%s' - please submit a bug report or patch" backend)))))
            (cons backend root-dir)))))))

(define-ibuffer-filter vc-root
    "Toggle current view to buffers with vc root dir QUALIFIER."
  (:description "vc root dir"
                :reader (read-from-minibuffer "Filter by vc root dir (regexp): "))
  (ibuffer-awhen (ibuffer-vc-root buf)
    (equal qualifier it)))

;;;###autoload
(defun ibuffer-vc-generate-filter-groups-by-vc-root ()
  "Create a set of ibuffer filter groups based on the vc root dirs of buffers"
  (let ((roots (ibuffer-remove-duplicates
                (delq nil (mapcar 'ibuffer-vc-root (buffer-list))))))
    (mapcar (lambda (vc-root)
              (cons (format "%s:%s" (car vc-root) (cdr vc-root))
                    `((vc-root . ,vc-root))))
            roots)))

;;;###autoload
(defun ibuffer-vc-set-filter-groups-by-vc-root ()
  "Set the current filter groups to filter by vc root dir."
  (interactive)
  (setq ibuffer-filter-groups (ibuffer-vc-generate-filter-groups-by-vc-root))
  (ibuffer-update nil t))


;;; Display vc status info in the ibuffer list

(defun ibuffer-vc--status-string ()
  (when (and buffer-file-name (ibuffer-vc--include-file-p buffer-file-name))
    (let ((state (vc-state buffer-file-name)))
      (if state
          (symbol-name state)
        "-"))))

;;;###autoload (autoload 'ibuffer-make-column-vc-status "ibuffer-vc")
(define-ibuffer-column vc-status
  (:name "VC status")
  (ibuffer-vc--status-string))

;;;###autoload (autoload 'ibuffer-make-column-vc-status-mini "ibuffer-vc")
(define-ibuffer-column vc-status-mini
  (:name "V")
  (if (and buffer-file-name (ibuffer-vc--include-file-p buffer-file-name))
      (let ((state (vc-state buffer-file-name)))
        (cond
         ((eq 'added state) "A")
         ((eq 'removed state) "D")
         ((eq 'up-to-date state) "@")
         ((eq 'edited state) "*")
         ((eq 'needs-update state) "O")
         ((memq state '(conflict needs-merge unlocked-changes)) "!")
         ((eq 'ignored state) "I")
         ((memq state '(() unregistered missing)) "?")))
    " "))

;;;###autoload (autoload 'ibuffer-do-sort-by-vc-status "ibuffer-vc")
(define-ibuffer-sorter vc-status
  "Sort the buffers by their vc status."
  (:description "vc status")
  (let ((file1 (with-current-buffer (car a)
                 buffer-file-name))
        (file2 (with-current-buffer (car b)
                 buffer-file-name)))
    (if (and file1 file2)
        (string-lessp (with-current-buffer (car a)
                        (ibuffer-vc--status-string))
                      (with-current-buffer (car b)
                        (ibuffer-vc--status-string)))
      (not (null file1)))))


(provide 'ibuffer-vc)
;;; ibuffer-vc.el ends here
