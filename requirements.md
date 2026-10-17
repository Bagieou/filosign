# Requirements Documentation
**FiloSign - Mobile-based cross-platform application for Filipino Sign Language learning**

---

## 1. Functional Requirements

### 1.1 Sign-in Module
1. The system shall enable existing users to open their account using their email and password to their learning progress, successfully within 3 seconds.
2. The system shall enable existing users to sign-in via an OTP code sent to the user's email.
3. The system shall enable existing users to reset forgotten password, only after an OTP verification.
4. The system shall allow users to access the sign-up module within 2 seconds.

### 1.2 Sign-up Module
5. The system shall allow new users to successfully create an account after a confirmation via an OTP after they provide their user name, email address, and password.

### 1.3 User Settings Module
6. The system shall allow access to the User Settings Module from the homepage within 2 seconds.
7. The system shall allow the changing of an existing user's passwords only after an OTP reauthentication. Changes will be saved if the new password meets a minimum of 8 characters in length, one special character, and one capital letter.
8. The system shall allow the editing of an existing user's email through the settings module. Only after email verification to both existing and new emails shall the information be saved.
9. The system shall allow users to edit their username.
10. The system shall allow users to sign-out from the application and redirect to the sign-in page within 2 seconds.
11. The system shall let users delete their account, only after an OTP reauthentication.

### 1.4 Homepage Module
12. The system, upon user login, shall provide an overview of the learner's progress by displaying a homepage.
13. The system shall allow users to search for any unlocked signs across the entire system in less than 3 seconds, by having a search bar directly integrated into the homepage.
14. The system shall ensure that features are accessible through dedicated navigation icons on the homepage that are visible on desktop and mobile screen sizes.

### 1.5 Learning Section
15. The system shall allow access to the Learn feature from the homepage within 2 seconds.
16. The system shall facilitate skill learning through delivering a category-based lessons divided into distinct categories.

### 1.6 Quiz Feature
17. The system shall require prerequisite mastery before users can access specific categories by lesson locking. A category is considered mastered if the user scores 90% on its quiz.
18. The system will ensure that unintended gestures will not be registered, by requiring the recognized sign to maintain a confidence score above 85% for a minimum of five consecutive frames before registering a result, therefore minimizing incorrect positive feedback.
19. The system shall redirect to the video lesson showing the correct signing if the user fails after three consecutive attempts to achieve the right sign.

### 1.7 Practice Feature
20. The system shall allow users to develop and practice their signing skills by providing a sign practice environment with videos of signs.
21. The system shall allow access to the practice environment from the homepage Practice icon or from search entries in 3 seconds.
22. The system shall register a correct sign when 85% matches the target sign.
23. The system shall provide visual feedback within 1 second after the user performs a sign.

### 1.8 Search Feature
24. The system shall provide an easy access to all Filipino Sign Languages featured throughout the system through a search feature which will provide the correct sign in less than 2 seconds.
25. The system shall allow users to access the search feature through the homepage.

### 1.9 User Database Management
26. The system shall store user information such as names, emails, passwords linked to accounts with a user ID.
27. The system shall track and store learning progress data such as completed lessons, and quiz scores linked to accounts.

### 1.10 Content Storage and Delivery
28. The system shall ensure efficient loading and playback of video lessons, quiz, and search entries within 5 seconds for a broadband connection of at least 5Mbps, and for slower connections, videos will be delivered in a lower quality to prevent buffering.

### 1.11 Authentication and Security
29. The system shall protect user data by implementing secure authentication through email and password verification, and proper password hashing and session management.

### 1.12 Recognition Accuracy
30. The system shall consistently recognize FSL signs under controlled light conditions, with a minimum average recognition accuracy of 85% across all sign classes as measured during model testing.
31. The system shall complete sign classification within one second after a 30-frame hand landmark sequence has been fully captured by the application.
32. The system shall collect a sequence of 30 consecutive frames of hand landmark data at a minimum of 15 frames per second before submitting the sequence to the LSTM model for dynamic sign classification.

### 1.13 Occlusion Handling
33. The system shall detect poor lighting conditions that may affect recognition accuracy and provide a notification on screen.
34. The system shall ensure that the hand is fully visible in the frame by verifying that the detected hand bounding box does not intersect with the image edges, with a margin of error of less than 10%, and when this requirement is not fulfilled, a warning message will be displayed.
35. The system shall provide accurate recognition performance by ensuring that the system works with a camera that has a minimum resolution of 640x640 pixels. When this is not met, a notification will be displayed.

---

## 2. Non-Functional Requirements

### 2.1 Security Requirements
36. The system shall hash user's password with Argon2ID for strong protection against credential attacks.
37. The system shall enforce session timeout, automatically logging out users after 15 minutes of inactivity.
38. The system shall implement account lockout after 5 consecutive failed login attempts, with a 15-minute cooldown before retrying.
39. The system shall implement OTP verification on the sign-up page.
40. The system shall comply with the Data Privacy Act of 2012 (Republic Act No. 10173). All camera processing remains client-side; no video data is transmitted to or stored on the server.

### 2.2 Performance Requirements
41. The system shall load the homepage within 2 seconds on a 5 Mbps broadband connection.
42. The system shall complete sign inference within 1 second across devices.
43. The system shall return search results within 2 seconds for queries against the 130-sign library.

### 2.3 Reliability Requirements
44. The system shall perform automated weekly backups of the user database to prevent data loss.
45. The system shall preserve data integrity such that quiz scores and lesson progress remain consistent across sessions.

### 2.4 Usability Requirements
46. The system shall provide a user-friendly interface enabling new users to complete sign-up and start their first lesson within 5 minutes of first access using only the built-in onboarding tooltips.
47. The system shall be responsive and accessible across desktops, tablets, and mobile devices.

### 2.5 Maintainability and Scalability Requirements
48. The system shall allow updates or changes without affecting stored data.
49. The system shall support up to 100 concurrent user sessions while maintaining a page load and database query response time within 2 seconds.

### 2.6 Compatibility Requirements
50. The system shall run on both Android and iOS.