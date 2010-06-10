
(asdf:oos 'asdf:load-op 'cl-oauth)
(asdf:oos 'asdf:load-op 'hunchentoot)

(defpackage :cl-oauth.google-consumer
  (:use :cl :cl-oauth))

(in-package :cl-oauth.google-consumer)

;;; insert your credentials and auxiliary information here.
(defparameter *key* "")
(defparameter *secret* "")
(defparameter *callback-uri* "")
(defparameter *callback-port* 8090
  "Port to listen on for the callback")


;;; go
(defparameter *get-request-token-endpoint* "https://www.google.com/accounts/OAuthGetRequestToken")
(defparameter *auth-request-token-endpoint* "https://www.google.com/accounts/OAuthAuthorizeToken")
(defparameter *get-access-token-endpoint* "https://www.google.com/accounts/OAuthGetAccessToken")
(defparameter *consumer-token* (make-consumer-token :key *key* :secret *secret*))
(defparameter *request-token* nil)
(defparameter *access-token* nil)

(defun get-access-token ()
  (obtain-access-token *get-access-token-endpoint* *request-token*))

;;; get a request token
(defun get-request-token (scope)
  ;; TODO: scope could be a list.
  (obtain-request-token
    *get-request-token-endpoint*
    *consumer-token*
    :callback-uri *callback-uri*
    :user-parameters `(("scope" . ,scope))))

(setf *request-token* (get-request-token "http://www.google.com/calendar/feeds/"))

(let ((auth-uri (make-authorization-uri *auth-request-token-endpoint* *request-token*)))
  (format t "Please authorize the request token at this URI: ~A~%" (puri:uri auth-uri)))


;;; set up callback uri
(defun callback-dispatcher (request)
  (declare (ignorable request))
  (unless (cl-ppcre:scan  "favicon\.ico$" (hunchentoot:script-name request))
    (lambda (&rest args)
      (declare (ignore args))
      (handler-case
          (authorize-request-token-from-request
            (lambda (rt-key)
              (assert *request-token*)
              (unless (equal (url-encode rt-key) (token-key *request-token*))
                (warn "Keys differ: ~S / ~S~%" (url-encode rt-key) (token-key *request-token*)))
              *request-token*))
        (error (c)
          (warn "Couldn't verify request token authorization: ~A" c)))
      (when (request-token-authorized-p *request-token*)
        (format t "Successfully verified request token with key ~S~%" (token-key *request-token*))
        (setf *access-token* (get-access-token))
        ;; test request:
        (let ((result (access-protected-resource
                        "http://www.google.com/calendar/feeds/default/allcalendars/full?orderby=starttime"
                        *access-token*)))
          (if (stringp result)
            result
            (babel:octets-to-string result)))))))

(pushnew 'callback-dispatcher hunchentoot:*dispatch-table*)


(defvar *web-server* nil)

(when *web-server*
  (hunchentoot:stop *web-server*)
  (setf *web-server* nil))

(setf *web-server* (hunchentoot:start (make-instance 'hunchentoot:acceptor :port *callback-port*)))

